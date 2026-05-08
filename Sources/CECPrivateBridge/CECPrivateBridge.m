#import "CECPrivateBridge.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <string.h>

typedef struct {
    unsigned char bytes[8];
} CECUserControl;

static void TVCECSetMessage(char **messagePointer, NSString *message) {
    if (messagePointer == NULL) {
        return;
    }

    const char *utf8 = message.UTF8String ?: "Unknown private IOCEC error.";
    *messagePointer = strdup(utf8);
}

static BOOL TVCECLoadFrameworks(char **errorMessage) {
    void *coreRC = dlopen("/System/Library/PrivateFrameworks/CoreRC.framework/CoreRC", RTLD_NOW);
    void *ioCEC = dlopen("/System/Library/PrivateFrameworks/IOCEC.framework/IOCEC", RTLD_NOW);

    if (coreRC == NULL || ioCEC == NULL) {
        const char *details = dlerror();
        TVCECSetMessage(errorMessage, [NSString stringWithFormat:@"无法加载 Apple 私有 CEC 框架。%@", details ? [NSString stringWithUTF8String:details] : @""]);
        return NO;
    }

    return YES;
}

static id TVCECCreateInterface(char **errorMessage) {
    if (!TVCECLoadFrameworks(errorMessage)) {
        return nil;
    }

    Class CECInterface = NSClassFromString(@"CECInterface");
    if (CECInterface == Nil) {
        TVCECSetMessage(errorMessage, @"系统中没有找到 CECInterface。");
        return nil;
    }

    id interface = ((id (*)(id, SEL))objc_msgSend)((id)CECInterface, @selector(alloc));
    interface = ((id (*)(id, SEL))objc_msgSend)(interface, @selector(init));
    if (interface == nil) {
        TVCECSetMessage(errorMessage, @"无法创建 CECInterface。");
    }

    return interface;
}

static BOOL TVCECSendMessage(id interface, id message, NSString *failurePrefix, NSMutableArray<NSString *> *sentMessages, NSMutableArray<NSString *> *errors) {
    NSError *error = nil;
    BOOL ok = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(
        interface,
        @selector(sendMessage:error:),
        message,
        &error
    );

    if (ok) {
        [sentMessages addObject:[message description]];
    } else {
        [errors addObject:[NSString stringWithFormat:@"%@：%@", failurePrefix, error.localizedDescription ?: @"系统拒绝发送 CEC 命令"]];
    }

    return ok;
}

bool TVCECPrivateCheck(char **errorMessage) {
    @autoreleasepool {
        id interface = TVCECCreateInterface(errorMessage);
        if (interface == nil) {
            return false;
        }

        NSDictionary *properties = nil;
        if ([interface respondsToSelector:@selector(properties)]) {
            properties = ((id (*)(id, SEL))objc_msgSend)(interface, @selector(properties));
        }

        TVCECSetMessage(errorMessage, [NSString stringWithFormat:@"Apple 私有 IOCEC 可用。\n\n%@", properties ?: @{}]);
        return true;
    }
}

bool TVCECPrivateSendUserControl(uint8_t command, char **errorMessage) {
    @autoreleasepool {
        id interface = TVCECCreateInterface(errorMessage);
        if (interface == nil) {
            return false;
        }

        Class CECMessage = NSClassFromString(@"CECMessage");
        if (CECMessage == Nil) {
            TVCECSetMessage(errorMessage, @"系统中没有找到 CECMessage。");
            return false;
        }

        CECUserControl control = { .bytes = { command, 0, 0, 0, 0, 0, 0, 0 } };
        id press = ((id (*)(id, SEL, CECUserControl, unsigned char, unsigned char))objc_msgSend)(
            (id)CECMessage,
            @selector(userControlPressed:from:to:),
            control,
            4,
            0
        );
        id release = ((id (*)(id, SEL, unsigned char, unsigned char))objc_msgSend)(
            (id)CECMessage,
            @selector(userControlReleasedFrom:to:),
            4,
            0
        );

        NSMutableArray<NSString *> *sentMessages = [NSMutableArray array];
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        BOOL pressOK = TVCECSendMessage(interface, press, @"按下命令失败", sentMessages, errors);
        BOOL releaseOK = TVCECSendMessage(interface, release, @"释放命令失败", sentMessages, errors);

        if (!pressOK || !releaseOK) {
            TVCECSetMessage(errorMessage, [errors componentsJoinedByString:@"\n"]);
            return false;
        }

        TVCECSetMessage(errorMessage, [NSString stringWithFormat:@"已发送：\n%@", [sentMessages componentsJoinedByString:@"\n"]]);
        return true;
    }
}

bool TVCECPrivateBecomeActiveSource(char **errorMessage) {
    @autoreleasepool {
        id interface = TVCECCreateInterface(errorMessage);
        if (interface == nil) {
            return false;
        }

        Class CECMessage = NSClassFromString(@"CECMessage");
        if (CECMessage == Nil) {
            TVCECSetMessage(errorMessage, @"系统中没有找到 CECMessage。");
            return false;
        }

        unsigned char playbackDevice1 = 4;
        unsigned char tv = 0;
        unsigned short macPhysicalAddress = 0x1000;

        id imageViewOn = ((id (*)(id, SEL, unsigned char, unsigned char))objc_msgSend)(
            (id)CECMessage,
            @selector(imageViewOnFrom:to:),
            playbackDevice1,
            tv
        );
        id textViewOn = ((id (*)(id, SEL, unsigned char, unsigned char))objc_msgSend)(
            (id)CECMessage,
            @selector(textViewOnFrom:to:),
            playbackDevice1,
            tv
        );
        id activeSource = ((id (*)(id, SEL, unsigned char, unsigned short))objc_msgSend)(
            (id)CECMessage,
            @selector(activeSourceFrom:physicalAddress:),
            playbackDevice1,
            macPhysicalAddress
        );

        NSMutableArray<NSString *> *sentMessages = [NSMutableArray array];
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        BOOL imageOK = TVCECSendMessage(interface, imageViewOn, @"Image View On 失败", sentMessages, errors);
        BOOL textOK = TVCECSendMessage(interface, textViewOn, @"Text View On 失败", sentMessages, errors);
        BOOL activeOK = TVCECSendMessage(interface, activeSource, @"Active Source 失败", sentMessages, errors);

        if (!imageOK || !textOK || !activeOK) {
            TVCECSetMessage(errorMessage, [errors componentsJoinedByString:@"\n"]);
            return false;
        }

        TVCECSetMessage(errorMessage, [NSString stringWithFormat:@"已发送信号源切换序列：\n%@", [sentMessages componentsJoinedByString:@"\n"]]);
        return true;
    }
}

void TVCECPrivateFreeMessage(char *message) {
    free(message);
}
