// CGEvent 鼠标注入。osascript 的 `click at {x,y}` 在 Simulator 上必失败（error -25204），
// 必须走 CGEvent。坐标为 macOS 屏幕坐标，由 driver.sh 从设备像素换算。
import Foundation
import CoreGraphics

let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)

func post(_ t: CGEventType, _ p: CGPoint) {
  CGEvent(mouseEventSource: src, mouseType: t,
          mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

if a.count >= 6, a[1] == "drag" {
  let x1 = Double(a[2])!, y1 = Double(a[3])!, x2 = Double(a[4])!, y2 = Double(a[5])!
  post(.mouseMoved, CGPoint(x: x1, y: y1));   usleep(150_000)
  post(.leftMouseDown, CGPoint(x: x1, y: y1)); usleep(150_000)
  let steps = 28
  for i in 1...steps {
    let t = Double(i) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t))
    usleep(16_000)                       // ~60fps，太快 Flutter 收不到连续 drag
  }
  usleep(250_000)                        // 松手前停顿，RefreshIndicator 才会触发
  post(.leftMouseUp, CGPoint(x: x2, y: y2))
} else if a.count >= 3 {
  let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
  post(.mouseMoved, p);    usleep(120_000)
  post(.leftMouseDown, p); usleep(90_000)
  post(.leftMouseUp, p)
}
