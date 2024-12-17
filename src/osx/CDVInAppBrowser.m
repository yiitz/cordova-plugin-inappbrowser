/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVInAppBrowser.h"
#import <Cordova/CDVPluginResult.h>

#define    kInAppBrowserTargetSelf @"_self"
#define    kInAppBrowserTargetSystem @"_system"
#define    kInAppBrowserTargetBlank @"_blank"


@interface CDVInAppBrowserWindowController : NSWindowController <WKNavigationDelegate>
@property (strong) WKWebView *webView;
@end

@interface CDVInAppBrowser()
@property (nonatomic, strong) InAppBrowserViewController *browserController;
@end

@implementation CDVInAppBrowser

- (void)pluginInitialize
{
}

- (BOOL) isSystemUrl:(NSURL*)url
{
    if ([[url host] isEqualToString:@"itunes.apple.com"]) {
        return YES;
    }

    return NO;
}

- (void)open:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult;

    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kInAppBrowserTargetSelf];

    self.callbackId = command.callbackId;

    if (url != nil) {

        NSURL* baseUrl = [NSURL URLWithString:url];

        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];

        if ([self isSystemUrl:absoluteUrl]) {
            target = kInAppBrowserTargetSystem;
        }

        if ([target isEqualToString:kInAppBrowserTargetSelf]) {
            //[self openInCordovaWebView:absoluteUrl withOptions:options];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not Yet Implemented for OSX: [self openInCordovaWebView:absoluteUrl withOptions:options]"];
        } else if ([target isEqualToString:kInAppBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else { // _blank or anything else
            //[self openInInAppBrowser:absoluteUrl withOptions:options];
            // 创建并打开浏览器窗口
            dispatch_async(dispatch_get_main_queue(), ^{
                InAppBrowserViewController *browserController = [[InAppBrowserViewController alloc] initWithURL:absoluteUrl];
                browserController.onLoadStart = ^(NSURL *url) {
                    // 回调 loadstart 事件
                    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
                    [result setKeepCallbackAsBool:YES];
                    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                };
                browserController.onExit = ^{
                    // 回调 exit 事件
                    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsDictionary:@{@"type":@"exit"}];
                    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                };
                self.browserController = browserController;
                [browserController showWindow:browserController];
            });
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)openInSystem:(NSURL*)url
{
    [[NSWorkspace sharedWorkspace] openURL:url];
}

// 关闭窗口
- (void)close:(CDVInvokedUrlCommand*)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.browserController close];
        self.browserController = nil;
    });
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [result setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

@end


@implementation InAppBrowserViewController

- (instancetype)initWithURL:(NSURL*)url {
    self = [super initWithWindow:nil];
    if (self) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"Browser";
        
        WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:config];
        webView.navigationDelegate = self;
        webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.window.contentView = webView;
        
        [webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
    return self;
}

- (void)webView:(WKWebView *)theWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL* url = navigationAction.request.URL;
    NSURL* mainDocumentURL = navigationAction.request.mainDocumentURL;
    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];
    
    if (self.onLoadStart && isTopLevelNavigation) {
        self.onLoadStart(url);
    }

    // Fix GH-417 & GH-424: Handle non-default target attribute
    // Based on https://stackoverflow.com/a/25713070/777265
    if (!navigationAction.targetFrame){
        [theWebView loadRequest:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel);
    }else{
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

// TODO by yiitz: Manually clicking to close the window here will not trigger a callback.
- (void)close {
    [self.window close];
    if (self.onExit) {
        self.onExit();
    }
}

@end
