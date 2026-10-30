// Done animations (CLAUDE.md 8, Settings › Done animation): a small moment when an entry is completed, and a
// quieter one when it is cancelled. Pure decoration in Core Animation over the page: the entry has already
// changed when it plays. Timings are the PWA's (its mockup ×1.4), played at 60% of that speed (Fernando). Reduce Motion turns them off.
import UIKit

enum DoneAnimation: String, CaseIterable, Identifiable {
    case ink, pop, ripple, sparks, highlighter, settle, colorSparks
    var id: String { rawValue }
    var name: String { S.doneAnimations[rawValue] ?? rawValue }
    var hint: String { S.doneAnimationHints[rawValue] ?? "" }

    static var current: DoneAnimation { DoneAnimation(rawValue: UserDefaults.standard.string(forKey: "doneAnimation") ?? "") ?? .ink }
}

enum DoneFx {
    private static let slow = 1.4 / 0.6
    private static let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)

    /// `bullet`: the view around the glyph; `mark`: the glyph (×, ✓) that comes in; `host` and `textRect`: the
    /// line's words, for Highlighter and Settle.
    static func play(
        _ style: DoneAnimation = .current, cancel: Bool, check: Bool, bullet: UIView, mark: UIView?, color: UIColor,
        host: UIView?, textRect: CGRect?
    ) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // The mark comes in on every style: a check drawn left to right like a pen stroke; a cross stamped (a
        // half-revealed × would read as ">").
        if !cancel, let mark {
            if check { reveal(mark) } else { stamp(mark) }
        }
        let center = bullet.superview.map { bullet.convert(CGPoint(x: bullet.bounds.midX, y: bullet.bounds.midY), to: $0) }
        switch style {
        case .ink:
            break
        case .pop:
            pop(bullet, to: cancel ? 1.15 : 1.45, duration: cancel ? 0.26 : 0.32)
        case .ripple:
            if let host = bullet.superview, let center { ripple(in: host, at: center, color: color, cancel: cancel) }
        case .sparks, .colorSparks:
            if let host = bullet.superview, let center { sparks(in: host, at: center, color: color, colored: style == .colorSparks, cancel: cancel) }
        case .highlighter:
            if let host, let textRect { highlight(in: host, rect: textRect, color: cancel ? UIColor.systemGray.withAlphaComponent(0.14) : color.withAlphaComponent(0.22)) }
        case .settle:
            if let host, let textRect { nudge(in: host, rect: textRect, by: cancel ? 2 : 5, duration: cancel ? 0.3 : 0.36) }
        }
    }

    private static func animation(_ key: String, duration: Double, delay: Double = 0) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.duration = duration * slow
        a.beginTime = delay > 0 ? CACurrentMediaTime() + delay * slow : 0
        a.timingFunction = ease
        a.fillMode = .backwards
        return a
    }

    private static func stamp(_ v: UIView) {
        let scale = animation("transform.scale", duration: 0.24, delay: 0.04)
        scale.fromValue = 0.4
        scale.toValue = 1
        let fade = animation("opacity", duration: 0.24, delay: 0.04)
        fade.fromValue = 0
        fade.toValue = 1
        v.layer.add(scale, forKey: "fx-stamp")
        v.layer.add(fade, forKey: "fx-stamp-fade")
    }

    private static func reveal(_ v: UIView) {
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 0.5)
        mask.frame = v.layer.bounds
        v.layer.mask = mask
        let grow = animation("bounds.size.width", duration: 0.26, delay: 0.06)
        grow.fromValue = 0
        grow.toValue = v.layer.bounds.width
        CATransaction.begin()
        CATransaction.setCompletionBlock { v.layer.mask = nil }
        mask.add(grow, forKey: "fx-mark")
        CATransaction.commit()
    }

    private static func pop(_ v: UIView, to peak: Double, duration: Double) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, peak, 1]
        a.keyTimes = [0, 0.4, 1]
        a.duration = duration * slow
        a.timingFunctions = [ease, ease]
        v.layer.add(a, forKey: "fx-pop")
    }

    /// A shape added for the animation and removed when it ends.
    private static func once(_ layer: CALayer, in host: UIView, _ animations: [CAAnimation], duration: Double) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration * slow
        group.timingFunction = ease
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.opacity = 0
        host.layer.addSublayer(layer)
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(group, forKey: "fx")
        CATransaction.commit()
    }

    private static func ripple(in host: UIView, at center: CGPoint, color: UIColor, cancel: Bool) {
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        ring.position = center
        ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 1.5
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = cancel ? 2.4 : 3.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = cancel ? 0.3 : 0.55
        fade.toValue = 0
        once(ring, in: host, [scale, fade], duration: 0.52)
    }

    private static func sparks(in host: UIView, at center: CGPoint, color: UIColor, colored: Bool, cancel: Bool) {
        let tints = [Theme.ui("task"), Theme.ui("event"), Theme.ui("note")]
        let size: CGFloat = colored ? 5 : 4
        let distance: CGFloat = cancel ? 10 : 16
        for i in 0..<6 {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.position = center
            dot.backgroundColor = (colored ? tints[i % 3] : color).resolvedColor(with: host.traitCollection).cgColor
            let angle = CGFloat(i) * .pi / 3
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = center
            move.toValue = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 0.4
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = cancel ? 0.4 : 0.9
            fade.toValue = 0
            once(dot, in: host, [move, scale, fade], duration: 0.48)
        }
    }

    /// A soft swipe of the bullet's color behind the words, then it fades.
    private static func highlight(in host: UIView, rect: CGRect, color: UIColor) {
        let band = CALayer()
        band.backgroundColor = color.resolvedColor(with: host.traitCollection).cgColor
        band.cornerRadius = 4
        band.anchorPoint = CGPoint(x: 0, y: 0.5)
        let r = rect.insetBy(dx: -4, dy: rect.height * 0.12)
        band.bounds = CGRect(origin: .zero, size: r.size)
        band.position = CGPoint(x: r.minX, y: r.midY)
        let sweep = CAKeyframeAnimation(keyPath: "transform.scale.x")
        sweep.values = [0, 1, 1]
        sweep.keyTimes = [0, 0.55, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.55, 1]
        // Behind the text: the text view draws its words in a subview above its own layer's sublayers.
        band.opacity = 0
        host.layer.insertSublayer(band, at: 0)
        let group = CAAnimationGroup()
        group.animations = [sweep, fade]
        group.duration = 0.64 * slow
        group.timingFunction = ease
        CATransaction.begin()
        CATransaction.setCompletionBlock { band.removeFromSuperlayer() }
        band.add(group, forKey: "fx")
        CATransaction.commit()
    }

    /// The line takes a small breath to the right: a picture of its words moves over a patch of paper.
    private static func nudge(in host: UIView, rect: CGRect, by distance: CGFloat, duration: Double) {
        guard let picture = host.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        let cover = UIView(frame: rect)
        // The color behind the words: the page's paper (the editor is see-through), or the host's own.
        cover.backgroundColor = host is UITextView ? Theme.ui("paper") : host.backgroundColor ?? Theme.ui("paper")
        cover.isUserInteractionEnabled = false
        picture.frame = rect
        picture.isUserInteractionEnabled = false
        host.addSubview(cover)
        host.addSubview(picture)
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, distance, 0]
        a.keyTimes = [0, 0.4, 1]
        a.duration = duration * slow
        a.timingFunctions = [ease, ease]
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            picture.removeFromSuperview()
            cover.removeFromSuperview()
        }
        picture.layer.add(a, forKey: "fx")
        CATransaction.commit()
    }
}
