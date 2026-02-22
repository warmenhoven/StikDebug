//
//  ideviceinfo.c
//  StikDebug
//
//  Created by Stephen on 8/2/25.
//

#include <stdlib.h>
#include <arpa/inet.h>
#include "ideviceinfo.h"
#include "idevice.h"
#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
@import Foundation;

NSError* makeError(int code, NSString* msg);
LockdowndClientHandle* ideviceinfo_c_init(IdeviceProviderHandle* g_provider, IdevicePairingFile* g_sess_pf, NSError** error) {
    LockdowndClientHandle *g_client = NULL;
    IdeviceFfiError *err = lockdownd_connect(g_provider, &g_client);
    if (err) {
        *error = makeError(err->code, @(err->message));
        idevice_pairing_file_free(g_sess_pf);
        idevice_error_free(err);
        return NULL;
    }

    err = lockdownd_start_session(g_client, g_sess_pf);
    idevice_pairing_file_free(g_sess_pf);
    if (err) {
        *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        lockdownd_client_free(g_client);
        return NULL;
    }

    return g_client;
}

char *ideviceinfo_c_get_xml(LockdowndClientHandle* g_client, NSError** error) {
    if (!g_client) {
        return NULL;
    }

    void *plist_obj = NULL;
    struct IdeviceFfiError *err = lockdownd_get_value(g_client, NULL, NULL, &plist_obj);
    if (err) {
        *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        return NULL;
    }

    char *xml = NULL;
    uint32_t xml_len = 0;
    if (plist_to_xml(plist_obj, &xml, &xml_len) != 0 || !xml) {
        plist_free(plist_obj);
        return NULL;
    }
    plist_free(plist_obj);
    return xml;
}

@implementation JITEnableContext(DeviceInfo)

- (LockdowndClientHandle*)ideviceInfoInit:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if (*error) { return nil; }
    IdevicePairingFile *pf = [self getPairingFileWithError:error];
    if (*error) { return nil; }
    return ideviceinfo_c_init(provider, pf, error);
}

- (char*)ideviceInfoGetXMLWithLockdownClient:(LockdowndClientHandle*)lockdownClient error:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if (*error) { return NULL; }
    return ideviceinfo_c_get_xml(lockdownClient, error);
}
@end
