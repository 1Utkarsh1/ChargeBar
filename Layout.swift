import Foundation
import CoreGraphics

func panelFrameOnScreen(_ frame: CGRect, visibleScreen: CGRect) -> CGRect {
    let bounds = visibleScreen.insetBy(dx: 8, dy: 8)
    var result = frame
    result.origin.x = max(bounds.minX, min(result.minX, bounds.maxX - result.width))
    result.origin.y = max(bounds.minY, min(result.minY, bounds.maxY - result.height))
    return result
}
