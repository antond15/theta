/* Looks up a Giphy GIF title from its ID (Copy GIF Name in CommentTextCopy.m). */

@interface IGGifOverlayManager : NSObject
+ (void)fetchGifName:(NSString *)mid completion:(void(^)(NSString *name))completion;
@end

@implementation IGGifOverlayManager

+ (void)fetchGifName:(NSString *)mid completion:(void(^)(NSString *name))completion {
    if (!mid || mid.length < 5 || !completion) {
        if (completion) completion(nil);
        return;
    }

    NSString *escapedID = [mid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    if (!escapedID) {
        completion(nil);
        return;
    }
    
    NSString *urlStr = [NSString stringWithFormat:@"https://giphy.com/gifs/%@", escapedID];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        completion(nil);
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.cachePolicy = NSURLRequestReturnCacheDataElseLoad;
    req.timeoutInterval = 10.0;
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil);
            return;
        }
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            completion(nil);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            completion(nil);
            return;
        }
        
        NSString *abs = response.URL.absoluteString;
        if (!abs || ![abs containsString:@"/gifs/"]) {
            completion(nil);
            return;
        }
        
        NSArray *components = [abs componentsSeparatedByString:@"/gifs/"];
        if (components.count < 2) {
            completion(nil);
            return;
        }
        
        NSString *slug = components[1];
        if (!slug || slug.length == 0) {
            completion(nil);
            return;
        }
        
        NSRange range = [slug rangeOfString:@"-" options:NSBackwardsSearch];
        if (range.location == NSNotFound || range.location == 0) {
            completion(nil);
            return;
        }
        
        NSString *raw = [slug substringToIndex:range.location];
        if (raw.length == 0) {
            completion(nil);
            return;
        }
        
        NSString *final = [[raw stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
        if (final.length == 0) {
            completion(nil);
            return;
        }
        
        completion(final);
    }] resume];
}

@end