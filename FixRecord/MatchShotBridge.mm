#import "MatchShotBridge.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/features2d.hpp>
#include <algorithm>
#include <cmath>
#include <vector>

@implementation MatchShotResult
@end

@implementation MatchShotBridge
+ (MatchShotResult *)compareBefore:(UIImage *)before after:(UIImage *)after {
    MatchShotResult *result = [MatchShotResult new];
    result.guidance = @"Alignment uncertain — use the ghost overlay.";
    result.confident = NO;
    result.inlierCount = 0;
    try {
        auto toMat = [](UIImage *image) {
            if (image.size.width <= 0 || image.size.height <= 0) return cv::Mat();
            CGFloat scale = std::min(1.0, 640.0 / std::max(image.size.width, image.size.height));
            CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = 1; format.opaque = YES;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
            UIImage *normalised = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
            }];
            CGImageRef cg = normalised.CGImage;
            if (!cg) return cv::Mat();
            size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
            cv::Mat mat((int)height, (int)width, CV_8UC4);
            CGColorSpaceRef colour = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(mat.data, width, height, 8, mat.step[0], colour, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
            CGColorSpaceRelease(colour);
            if (!context) return cv::Mat();
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
            CGContextRelease(context);
            return mat;
        };
        cv::Mat a = toMat(before), b = toMat(after);
        if (a.empty() || b.empty()) return result;
        auto prepare = [](cv::Mat &image) {
            double scale = std::min(1.0, 640.0 / std::max(image.cols, image.rows));
            if (scale < 1.0) cv::resize(image, image, cv::Size(), scale, scale, cv::INTER_AREA);
            cv::cvtColor(image, image, image.channels() == 4 ? cv::COLOR_RGBA2GRAY : cv::COLOR_RGB2GRAY);
            cv::equalizeHist(image, image);
        };
        prepare(a); prepare(b);
        auto orb = cv::ORB::create(450);
        std::vector<cv::KeyPoint> ka, kb;
        cv::Mat da, db;
        orb->detectAndCompute(a, cv::noArray(), ka, da);
        orb->detectAndCompute(b, cv::noArray(), kb, db);
        if (da.empty() || db.empty()) return result;
        std::vector<std::vector<cv::DMatch>> candidates;
        cv::BFMatcher(cv::NORM_HAMMING).knnMatch(da, db, candidates, 2);
        std::vector<cv::Point2f> pa, pb;
        for (const auto &pair : candidates) {
            if (pair.size() == 2 && pair[0].distance < 0.72f * pair[1].distance) {
                pa.push_back(ka[pair[0].queryIdx].pt); pb.push_back(kb[pair[0].trainIdx].pt);
            }
        }
        if (pa.size() < 12) return result;
        std::vector<double> allX, allY;
        for (size_t i = 0; i < pa.size(); ++i) { allX.push_back(pb[i].x / b.cols - pa[i].x / a.cols); allY.push_back(pb[i].y / b.rows - pa[i].y / a.rows); }
        auto median = [](std::vector<double> &v) { std::sort(v.begin(), v.end()); return v[v.size() / 2]; };
        double centreX = median(allX), centreY = median(allY);
        std::vector<double> dx, dy;
        for (size_t i = 0; i < pa.size(); ++i) {
            double x = pb[i].x / b.cols - pa[i].x / a.cols;
            double y = pb[i].y / b.rows - pa[i].y / a.rows;
            if (std::hypot(x - centreX, y - centreY) < 0.07) { dx.push_back(x); dy.push_back(y); }
        }
        result.inlierCount = dx.size();
        if (dx.size() < 10 || double(dx.size()) / pa.size() < 0.45) return result;
        result.confident = YES;
        double x = median(dx);
        double y = median(dy);
        if (std::abs(x) < 0.09 && std::abs(y) < 0.09) {
            result.wellAligned = YES;
            result.guidance = @"Good framing — review the pair before sharing.";
        }
        else if (std::abs(x) >= std::abs(y)) result.guidance = x > 0 ? @"Align slightly right." : @"Align slightly left.";
        else result.guidance = y > 0 ? @"Align slightly lower." : @"Align slightly higher.";
    } catch (...) {
        result.guidance = @"Alignment uncertain — use the ghost overlay.";
    }
    return result;
}
@end
