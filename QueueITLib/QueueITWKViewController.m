#import "QueueITWKViewController.h"
#import "QueueITEngine.h"

@interface QueueITWKViewController ()<WKNavigationDelegate>
@property (nonatomic) WKWebView* webView;
@property (nonatomic, strong) UIViewController* host;
@property (nonatomic, strong) QueueITEngine* engine;
@property (nonatomic, strong)NSString* queueUrl;
@property (nonatomic, strong)NSString* eventTargetUrl;
@property (nonatomic, strong)UIActivityIndicatorView* spinner;
@property (nonatomic, strong)NSString* customerId;
@property (nonatomic, strong)NSString* eventId;
@property BOOL isQueuePassed;
@property (nonatomic) CGRect* customFrame;
@end

static NSString * const JAVASCRIPT_GET_BODY_CLASSES = @"document.getElementsByTagName('body')[0].className";

@implementation QueueITWKViewController

-(instancetype)initWithHost:(UIViewController *)host
                queueEngine:(QueueITEngine*) engine
                   queueUrl:(NSString*)queueUrl
             eventTargetUrl:(NSString*)eventTargetUrl
                 customerId:(NSString*)customerId
                    eventId:(NSString*)eventId
{
    self = [super init];
    if(self) {
        self.host = host;
        self.engine = engine;
        self.queueUrl = queueUrl;
        self.eventTargetUrl = eventTargetUrl;
        self.customerId = customerId;
        self.eventId = eventId;
        self.isQueuePassed = NO;
    }
    return self;
}

- (void)close:(void (^ __nullable)(void))onComplete {
    [self.host dismissViewControllerAnimated:YES completion:^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        [self.view removeFromSuperview];
        if(onComplete!=nil){
            onComplete();
        }
    }];
}

- (BOOL) isTargetUrl:(nonnull NSURL*) targetUrl
      destinationUrl:(nonnull NSURL*) destinationUrl {
    NSString* destinationHost = destinationUrl.host;
    NSString* destinationPath = destinationUrl.path;
    NSString* targetHost = targetUrl.host;
    NSString* targetPath = targetUrl.path;
    
    return [destinationHost isEqualToString: targetHost]
    && [destinationPath isEqualToString: targetPath];
}

- (BOOL) isBlockedUrl:(nonnull NSURL*) destinationUrl {
    NSString* path = destinationUrl.path;
    if([path hasPrefix: @"/what-is-this.html"]){
        return true;
    }
    return false;
}

- (BOOL)handleSpecialUrls:(NSURL*) url
          decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler {
    if([[url absoluteString] isEqualToString: QueueCloseUrl]){
        [self close: ^{
            [self.engine raiseViewClosed];
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
        return true;
    } else if ([[url absoluteString] isEqualToString: QueueRestartSessionUrl]){
        [self close:^{
            [self.engine raiseSessionRestart];
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
        return true;
    }
    return NO;
}


- (CGSize)getFrameSize
{
    if(self.customFrame!=nil){
        CGFloat width = self.customFrame->size.width;
        CGFloat height = self.customFrame->size.height;
        if(width<0){
            width = self.view.bounds.size.width;
        }
        if(height<0){
            height = self.view.bounds.size.height;
        }
        return CGSizeMake(width, height);
    }
    return self.view.bounds.size;
}

- (CGPoint)getFrameOrigin
{
    if(self.customFrame!=nil){
        return self.customFrame->origin;
    }
    return self.view.bounds.origin;
}

- (CGRect)getFrame
{
    CGPoint origin = [self getFrameOrigin];
    CGSize size = [self getFrameSize];
    
    return CGRectMake(origin.x, origin.y, size.width, size.height);
}

- (void)setFrame:(CGRect*) rect
{
    self.customFrame = rect;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if(self.customFrame!=nil){
        [self.view setFrame: [self getFrame]];
    }
    
    CGSize webviewSize = [self getFrameSize];
    WKPreferences* preferences = [[WKPreferences alloc]init];
    preferences.javaScriptEnabled = YES;
    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc]init];
    config.preferences = preferences;
    WKWebView* view = [[WKWebView alloc]initWithFrame:CGRectMake(0, 0, webviewSize.width, webviewSize.height) configuration:config];
    view.navigationDelegate = self;
    self.webView = view;
    [self.webView setAutoresizingMask: UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth];
}

- (void)viewWillAppear:(BOOL)animated{
    CGSize webviewSize = [self getFrameSize];
    self.spinner = [[UIActivityIndicatorView alloc]initWithFrame:CGRectMake(0, 0, webviewSize.width, webviewSize.height)];
    [self.spinner setColor:[UIColor grayColor]];
    [self.spinner startAnimating];
    
    [self.view addSubview:self.webView];
    [self.webView addSubview:self.spinner];
    
    NSURL *urlAddress = [NSURL URLWithString:self.queueUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:urlAddress];
    [self.webView loadRequest:request];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(nonnull WKNavigationAction *)navigationAction decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler{
    
    if (!self.isQueuePassed) {
        NSURLRequest* request = navigationAction.request;
        NSString* urlString = [[request URL] absoluteString];
        NSString* targetUrlString = self.eventTargetUrl;
        NSLog(@"request Url: %@", urlString);
        NSLog(@"target Url: %@", targetUrlString);
        if (urlString != nil) {
            NSURL* url = [NSURL URLWithString:urlString];
            NSURL* targetUrl = [NSURL URLWithString:targetUrlString];
            if(urlString != nil && ![urlString isEqualToString:@"about:blank"]) {
                BOOL isQueueUrl = [self.queueUrl containsString:url.host];
                BOOL isNotFrame = [[[request URL] absoluteString] isEqualToString:[[request mainDocumentURL] absoluteString]];
                
                if([self handleSpecialUrls:url decisionHandler:decisionHandler]){
                    return;
                }
                
                if([self isBlockedUrl: url]){
                    decisionHandler(WKNavigationActionPolicyCancel);
                    return;
                }
                
                if (isNotFrame) {
                    if (isQueueUrl) {
                        [self.engine updateQueuePageUrl:urlString];
                    }
                    if ([self isTargetUrl: targetUrl
                           destinationUrl: url]) {
                        self.isQueuePassed = YES;
                        NSString* queueitToken = [self extractQueueToken:url.absoluteString];
                        [self.engine raiseQueuePassed:queueitToken];
                        decisionHandler(WKNavigationActionPolicyCancel);
                        [self close: nil];
                        return;
                    }
                }
                if (navigationAction.navigationType == WKNavigationTypeLinkActivated && !isQueueUrl) {
                    if (@available(iOS 10, *)){
                        [[UIApplication sharedApplication] openURL:[request URL] options:@{} completionHandler:^(BOOL success){
                            if (success){
                                NSLog(@"Opened %@",urlString);
                            }
                        }];
                    }
                    else {
                        [[UIApplication sharedApplication] openURL:[request URL]];
                    }
                    
                    decisionHandler(WKNavigationActionPolicyCancel);
                    return;
                }
            }
        }
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (NSString*)extractQueueToken:(NSString*) url {
    NSString* tokenKey = @"queueittoken=";
    if ([url containsString:tokenKey]) {
        NSString* token = [url substringFromIndex:NSMaxRange([url rangeOfString:tokenKey])];
        if([token containsString:@"&"]) {
            token = [token substringToIndex:NSMaxRange([token rangeOfString:@"&"]) - 1];
        }
        return token;
    }
    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    [self.spinner stopAnimating];
    if (![self.webView isLoading])
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    
    // Check if user exitted through the default exit link and notify the engine
    [self.webView evaluateJavaScript:JAVASCRIPT_GET_BODY_CLASSES completionHandler:^(id result, NSError* error){
        if (error != nil) {
            NSLog(@"evaluateJavaScript error : %@", error.localizedDescription);
        }
        else {
            NSString* resultString = [NSString stringWithFormat:@"%@", result];
            NSArray<NSString *> *htmlBodyClasses = [resultString componentsSeparatedByString:@" "];
            BOOL isExitClassPresent = [htmlBodyClasses containsObject:@"exit"];
            if (isExitClassPresent) {
                [self.engine raiseUserExited];
            }
        }
    }];
}

-(void)appWillResignActive:(NSNotification*)note
{
}

@end
