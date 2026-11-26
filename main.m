#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>
#import "Frames.h"

static NSString *const host = @"192.168.1.101";
static NSURL *endpoint(NSString *path) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/api/2/%@",host,path]];
}
// Called only on a worker queue. Serial control requests preserve start/stop ordering.
static BOOL streamControl(BOOL start) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint(@"viewfinder")];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 5;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = start ? @{@"viewfinder_active":@YES, @"viewfinder_streaming_port":@4001} : @{@"viewfinder_active":@NO};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL ok = NO;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        ok = !err && status >= 200 && status < 300;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return ok;
}

@interface Live : UIViewController
@property(atomic) NSUInteger generation;
@property(nonatomic,strong) UIImageView *picture;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *startButton;
@property(nonatomic,strong) dispatch_queue_t worker;
@end
@implementation Live
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Live view";
    self.worker = dispatch_queue_create("camera.viewfinder", DISPATCH_QUEUE_SERIAL);
    self.view.backgroundColor = UIColor.blackColor;
    self.picture = [UIImageView new];
    self.picture.contentMode = UIViewContentModeScaleAspectFit;
    self.status = [UILabel new];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = UIColor.whiteColor;
    self.status.numberOfLines = 0;
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"Connect to Bandit" forState:UIControlStateNormal];
    [self.startButton addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.picture,self.status,self.startButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12]]];
    [self.picture setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stop) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self stop]; }
- (void)stop { self.generation++; self.picture.image=nil; self.status.text=@"Join the camera’s Wi-Fi, then connect."; self.startButton.hidden=NO; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.status.text=@"Join the camera’s Wi-Fi, then connect."; }
- (void)connect {
    NSUInteger run = ++self.generation;
    self.startButton.hidden=YES; self.status.text=@"Connecting…";
    dispatch_async(self.worker, ^{
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in local = {.sin_len=sizeof(struct sockaddr_in),.sin_family=AF_INET,.sin_port=htons(4001),.sin_addr={.s_addr=htonl(INADDR_ANY)}};
        struct timeval timeout = {.tv_usec=250000};
        int bufferSize = 262144;
        FrameBuffer *frame = calloc(1,sizeof(FrameBuffer));
        BOOL ready = fd >= 0 && frame && setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)) == 0 && bind(fd,(struct sockaddr *)&local,sizeof(local)) == 0;
        if (ready) setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&bufferSize,sizeof(bufferSize));
        BOOL requested = ready && self.generation == run;
        BOOL active = requested && streamControl(YES);
        NSTimeInterval last = NSProcessInfo.processInfo.systemUptime;
        NSTimeInterval displayTime = 0;
        while (active && self.generation == run && NSProcessInfo.processInfo.systemUptime-last < 10) {
            @autoreleasepool {
                uint8_t packet[65536];
                struct sockaddr_in sender = {0}; socklen_t slen=sizeof(sender);
                ssize_t n=recvfrom(fd,packet,sizeof(packet),0,(struct sockaddr *)&sender,&slen);
                if (n<=0 || sender.sin_addr.s_addr != inet_addr(host.UTF8String)) continue;
                size_t length=assemble(frame,packet,(size_t)n);
                if (!length) continue;
                last=NSProcessInfo.processInfo.systemUptime;
                if (last-displayTime < 1.0/25) continue;
                displayTime=last;
                UIImage *image=[UIImage imageWithData:[NSData dataWithBytes:frame->bytes length:length]];
                if (image) dispatch_sync(dispatch_get_main_queue(), ^{
                    if (run == self.generation) { self.picture.image=image; self.status.text=nil; }
                });
            }
        }
        if (active) streamControl(NO);
        if (fd>=0) close(fd);
        free(frame);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (run==self.generation) {
                self.status.text=@"No live picture. Check camera Wi-Fi and Local Network access, then reconnect.";
                self.startButton.hidden=NO;
            }
        });
    });
}
@end

@interface Clips : UITableViewController
@property(nonatomic,copy) NSArray *clips;
@property(nonatomic) NSUInteger generation;
@end
@implementation Clips
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Recordings";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    [self refresh];
}
- (void)refresh {
    NSUInteger run=++self.generation;
    self.navigationItem.prompt=@"Reading camera…";
    [self page:0 collected:[NSMutableArray array] run:run];
}
- (void)page:(NSUInteger)offset collected:(NSMutableArray *)clips run:(NSUInteger)run {
    NSURL *url=endpoint([NSString stringWithFormat:@"videos?offset=%lu&count=30",(unsigned long)offset]);
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id page=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (run!=self.generation) return;
            if (![page isKindOfClass:NSDictionary.class] || ![page[@"total"] isKindOfClass:NSNumber.class]) {
                self.navigationItem.prompt=@"Check camera Wi-Fi and tap refresh."; return;
            }
            NSArray *items=page[@"items"];
            if (![items isKindOfClass:NSArray.class]) items=@[];
            for (id clip in items)
                if ([clip isKindOfClass:NSDictionary.class] && [clip[@"id"] isKindOfClass:NSString.class] && [clip[@"path"] isKindOfClass:NSString.class]) [clips addObject:clip];
            NSUInteger next=offset+items.count;
            if (items.count && next<[page[@"total"] unsignedIntegerValue]) { [self page:next collected:clips run:run]; return; }
            self.clips=clips; self.navigationItem.prompt=clips.count ? nil : @"No recordings on camera.";
            [self.tableView reloadData];
        });
    }] resume];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.clips.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"clip"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"clip"];
    NSDictionary *clip=self.clips[index.row];
    cell.textLabel.text=[clip[@"path"] lastPathComponent];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %.1f s",clip[@"resolution"] ?: @"Video",[clip[@"length_secs"] doubleValue]];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    NSString *identifier=[self.clips[index.row][@"id"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    NSURL *url=endpoint([NSString stringWithFormat:@"videos/%@/contents",identifier]);
    AVPlayerViewController *screen=[AVPlayerViewController new]; screen.player=[AVPlayer playerWithURL:url];
    [self presentViewController:screen animated:YES completion:^{ [screen.player play]; }];
}
@end
@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    Live *live=[Live new]; Clips *clips=[Clips new];
    UINavigationController *first=[[UINavigationController alloc] initWithRootViewController:live];
    UINavigationController *second=[[UINavigationController alloc] initWithRootViewController:clips];
    first.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Live" image:[UIImage systemImageNamed:@"viewfinder"] tag:0];
    second.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Recordings" image:[UIImage systemImageNamed:@"film"] tag:1];
    UITabBarController *tabs=[UITabBarController new]; tabs.viewControllers=@[first,second];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController=tabs;
    [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class)); } }
