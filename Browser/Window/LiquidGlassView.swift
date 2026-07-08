import AppKit
import SwiftUI

enum BrowserChromeGlassStyle {
    case clear
    case regular

    @available(macOS 26.0, *)
    var nsGlassEffectStyle: NSGlassEffectView.Style {
        switch self {
        case .clear:
            return .clear
        case .regular:
            return .regular
        }
    }
}

@available(macOS 26.0, *)
struct LiquidGlassView: NSViewRepresentable {
    let style: BrowserChromeGlassStyle
    let cornerRadius: CGFloat
    let maskedCorners: CACornerMask
    let tintColor: NSColor?

    private var usesAllCorners: Bool {
        maskedCorners == [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ]
    }

    init(
        style: BrowserChromeGlassStyle = .clear,
        cornerRadius: CGFloat,
        maskedCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ],
        tintColor: NSColor? = nil
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.maskedCorners = maskedCorners
        self.tintColor = tintColor
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSGlassEffectView) {
        view.wantsLayer = true
        view.style = style.nsGlassEffectStyle
        view.cornerRadius = usesAllCorners ? cornerRadius : 0
        view.tintColor = tintColor
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.maskedCorners = maskedCorners
        view.layer?.masksToBounds = true
    }
}

struct BrowserChromeBackground: View {
    enum Effect {
        case liquidGlass(style: BrowserChromeGlassStyle, tintColor: NSColor? = nil)
        case material
    }

    let bezelStyle: BrowserBezelStyle
    let cornerRadius: CGFloat
    let maskedCorners: CACornerMask
    let effect: Effect
    let accentColor: NSColor?
    let accentTintAlpha: CGFloat

    init(
        bezelStyle: BrowserBezelStyle,
        cornerRadius: CGFloat,
        maskedCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ],
        effect: Effect,
        accentColor: NSColor? = nil,
        accentTintAlpha: CGFloat = 0.44
    ) {
        self.bezelStyle = bezelStyle
        self.cornerRadius = cornerRadius
        self.maskedCorners = maskedCorners
        self.effect = effect
        self.accentColor = accentColor
        self.accentTintAlpha = accentTintAlpha
    }

    var body: some View {
        if bezelStyle.resolvedForCurrentOS == .simple {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: accentColor ?? .black))
        } else {
            switch effect {
            case .liquidGlass(let style, let tintColor):
                if #available(macOS 26.0, *) {
                    LiquidGlassView(
                        style: style,
                        cornerRadius: cornerRadius,
                        maskedCorners: maskedCorners,
                        tintColor: accentColor?.withAlphaComponent(accentTintAlpha) ?? tintColor
                    )
                } else {
                    materialFallback
                }
            case .material:
                materialFallback
            }
        }
    }

    private var materialFallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: accentColor ?? .windowBackgroundColor))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
    }
}
