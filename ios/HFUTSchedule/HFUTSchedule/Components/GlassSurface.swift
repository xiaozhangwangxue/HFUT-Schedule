import SwiftUI

private struct AdaptiveGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    @AppStorage(AppSettingsKey.liquidGlass) private var glass = true
    @AppStorage(AppSettingsKey.layerBlur) private var layerBlur = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if !glass || reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke((tint ?? .secondary).opacity(0.18), lineWidth: 0.7) }
        } else if #available(iOS 26.0, *), layerBlur {
            if let tint {
                content.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else if layerBlur {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        } else {
            content.background((tint ?? Color(uiColor: .secondarySystemBackground)).opacity(0.92),
                               in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func adaptiveGlass(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AdaptiveGlassModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

struct GlassIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .adaptiveGlass(cornerRadius: size * 0.34, tint: tint.opacity(0.14), interactive: true)
            .accessibilityHidden(true)
    }
}

/// A navigation link whose destination grows from the exact control that was
/// tapped on systems that support SwiftUI's zoom navigation transition.
///
/// Each link owns its namespace so reused identifiers in separate view trees
/// cannot collide. Reduced Motion and pre-iOS 18 systems retain ordinary,
/// fully interactive navigation.
struct SourceAnchoredNavigationLink<Destination: View, Label: View>: View {
    let sourceID: String
    private let destination: Destination
    private let label: Label

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettingsKey.transitionLevel) private var transitionLevel = 1
    @AppStorage(AppSettingsKey.sharedContainer) private var sharedContainer = true

    init(
        sourceID: String,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.sourceID = sourceID
        self.destination = destination()
        self.label = label()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *), !reduceMotion, transitionLevel > 0, sharedContainer {
            AppNavigationLink(title: PlatformNavigationCoordinator.title(for: destination)) {
                destination
                    .configuredPageTransition()
                    .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            } label: {
                label
                    .matchedTransitionSource(id: sourceID, in: namespace)
            }
        } else {
            AppNavigationLink(title: PlatformNavigationCoordinator.title(for: destination)) {
                destination.configuredPageTransition()
            } label: {
                label
            }
        }
    }
}

/// Configurable entrance effects supplement system navigation without replacing its gestures.
struct ConfiguredPageTransition: ViewModifier {
    @AppStorage(AppSettingsKey.transitionLevel) private var level = 1
    @AppStorage(AppSettingsKey.transitionSpeed) private var speed = 1.0
    @AppStorage(AppSettingsKey.transitionEffect) private var effect = "default"
    @AppStorage(AppSettingsKey.containerClips) private var clips = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    private var enabled: Bool { level > 0 && !reduceMotion }
    func body(content: Content) -> some View {
        content
            .opacity(!enabled || entered ? 1 : 0)
            .scaleEffect(enabled && effect == "scale" && !entered ? 0.94 : 1)
            .offset(x: enabled && effect == "push" && !entered ? (level == 2 ? 36 : 16) : 0)
            .clipShape(RoundedRectangle(cornerRadius: clips && !entered ? 20 : 0))
            .onAppear {
                guard enabled else { entered = true; return }
                withAnimation(.easeOut(duration: 0.3 / max(0.25, min(3, speed)))) { entered = true }
            }
    }
}
extension View {
    func configuredPageTransition() -> some View { modifier(ConfiguredPageTransition()) }
}
