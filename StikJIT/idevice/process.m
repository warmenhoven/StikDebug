//
//  process.m
//  StikDebug
//
//  Created by s s on 2025/12/12.
//

#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
@import Foundation;

// MARK: - Shared AppService session

typedef struct {
    AdapterHandle      *adapter;
    RsdHandshakeHandle *handshake;
    AppServiceHandle   *appService;
} AppServiceSession;

static void app_service_session_free(AppServiceSession *s) {
    if (s->appService) { app_service_free(s->appService);      s->appService = NULL; }
    if (s->handshake)  { rsd_handshake_free(s->handshake);     s->handshake  = NULL; }
    if (s->adapter)    { adapter_free(s->adapter);              s->adapter    = NULL; }
}

// Connects to the device via CoreDeviceProxy → Adapter → RSD → AppService.
// Returns 0 on success; cleans up any partial state and returns 1 on failure.
static int connect_app_service(IdeviceProviderHandle *provider,
                                AppServiceSession *out,
                                JITEnableContext *ctx,
                                NSError **outError)
{
    memset(out, 0, sizeof(*out));
    IdeviceFfiError *ffiError = NULL;

    CoreDeviceProxyHandle *coreProxy = NULL;
    ffiError = core_device_proxy_connect(provider, &coreProxy);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        return 1;
    }

    uint16_t rsdPort = 0;
    ffiError = core_device_proxy_get_server_rsd_port(coreProxy, &rsdPort);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to resolve RSD port"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        core_device_proxy_free(coreProxy);
        return 1;
    }

    ffiError = core_device_proxy_create_tcp_adapter(coreProxy, &out->adapter);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to create adapter"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        core_device_proxy_free(coreProxy);
        return 1;
    }
    coreProxy = NULL; // ownership transferred to adapter

    AdapterStreamHandle *stream = NULL;
    ffiError = adapter_connect(out->adapter, rsdPort, (ReadWriteOpaque **)&stream);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Adapter connect failed"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        app_service_session_free(out);
        return 1;
    }

    ffiError = rsd_handshake_new((ReadWriteOpaque *)stream, &out->handshake);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "RSD handshake failed"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        adapter_stream_close(stream);
        app_service_session_free(out);
        return 1;
    }
    stream = NULL; // consumed by handshake

    ffiError = app_service_connect_rsd(out->adapter, out->handshake, &out->appService);
    if (ffiError) {
        *outError = [ctx errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to open AppService"]
                                 code:ffiError->code];
        idevice_error_free(ffiError);
        app_service_session_free(out);
        return 1;
    }

    return 0;
}

// MARK: - JITEnableContext(Process)

@implementation JITEnableContext(Process)

- (NSArray<NSDictionary*>*)fetchProcessesViaAppServiceWithError:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if (*error) { return nil; }

    AppServiceSession session;
    if (connect_app_service(provider, &session, self, error) != 0) { return nil; }

    ProcessTokenC *processes = NULL;
    uintptr_t count = 0;
    IdeviceFfiError *ffiError = app_service_list_processes(session.appService, &processes, &count);

    NSMutableArray *result = nil;
    if (ffiError) {
        if (error) {
            *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to list processes"]
                                   code:ffiError->code];
        }
        idevice_error_free(ffiError);
    } else {
        result = [NSMutableArray arrayWithCapacity:count];
        for (uintptr_t idx = 0; idx < count; idx++) {
            ProcessTokenC proc = processes[idx];
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"pid"] = @(proc.pid);
            if (proc.executable_url) {
                entry[@"path"] = [NSString stringWithUTF8String:proc.executable_url];
            }
            [result addObject:entry];
        }
        if (processes && count > 0) {
            app_service_free_process_list(processes, count);
        }
    }

    app_service_session_free(&session);
    return result;
}

- (NSArray<NSDictionary*>*)_fetchProcessListLocked:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if (*error) { return nil; }
    return [self fetchProcessesViaAppServiceWithError:error];
}

- (NSArray<NSDictionary*>*)fetchProcessListWithError:(NSError**)error {
    __block NSArray *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(processInspectorQueue, ^{
        result = [self _fetchProcessListLocked:&localError];
    });
    if (error && localError) {
        *error = localError;
    }
    return result;
}

- (BOOL)killProcessWithPID:(int)pid error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if (*error) { return NO; }

    AppServiceSession session;
    if (connect_app_service(provider, &session, self, error) != 0) { return NO; }

    SignalResponseC *signalResponse = NULL;
    IdeviceFfiError *ffiError = app_service_send_signal(session.appService, (uint32_t)pid, SIGKILL, &signalResponse);

    BOOL success = NO;
    if (ffiError) {
        if (error) {
            *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to kill process"]
                                   code:ffiError->code];
        }
        idevice_error_free(ffiError);
    } else {
        success = YES;
    }

    if (signalResponse) { app_service_free_signal_response(signalResponse); }
    app_service_session_free(&session);
    return success;
}

@end
