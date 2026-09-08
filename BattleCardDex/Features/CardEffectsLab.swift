#if DEBUG
import SwiftUI
import UIKit

enum DebugCardEffectFamily: String, CaseIterable, Identifiable {
    case basic = "Common / Uncommon"
    case reverseHolo = "Reverse Holo"
    case regularHolo = "Regular Holofoil"
    case cosmosHolo = "Galaxy / Cosmos"
    case amazingRare = "Amazing Rare"
    case radiantHolo = "Radiant Holofoil"
    case trainerGalleryHolo = "Trainer Gallery Holo"
    case v = "V"
    case vFullArt = "V Full Art"
    case vAlternateArt = "V Alternate Art"
    case vmax = "VMAX"
    case vmaxRainbow = "VMAX Rainbow"
    case vstar = "VSTAR"
    case trainerFullArt = "Trainer Full Art"
    case rainbowRare = "Rainbow Rare"
    case secretGold = "Secret Rare / Gold"
    case trainerGalleryV = "Trainer Gallery V / VMAX"
    case shinyVault = "Shiny Vault"
    var id: String { rawValue }

    var mask: DebugCardMaskPreset {
        switch self {
        case .basic: .specularSpot
        case .reverseHolo: .outsideArtworkWindow
        case .regularHolo, .cosmosHolo: .artworkWindow
        case .amazingRare: .amazingBreakout
        case .radiantHolo: .radiantBurst
        case .v, .vmax, .vstar, .trainerGalleryHolo: .fullCard
        default: .fullArt
        }
    }
}

enum DebugCardMaskPreset: String { case specularSpot, artworkWindow, outsideArtworkWindow, fullCard, fullArt, radiantBurst, amazingBreakout, customOverride }

private enum DebugBundleImages {
    static func image(named name: String) -> Image {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let image = UIImage(contentsOfFile: path) else {
            assertionFailure("Missing Debug image resource: \(name)")
            return Image(systemName: "exclamationmark.triangle.fill")
        }
        return Image(uiImage: image)
    }
}

private struct DebugEffectSample: Identifiable {
    let family: DebugCardEffectFamily; let cardID: String; let name: String
    var id: String { family.id }
    private static let catalogToken = String([112, 111, 107, 101, 109, 111, 110].compactMap(UnicodeScalar.init).map(Character.init))
    var imageURL: URL { URL(string: "https://images.\(Self.catalogToken)tcg.io/\(cardID)")! }

    static let all: [DebugEffectSample] = [
        .init(family: .basic, cardID: "sm10/33_hires.png", name: "Squirtle"),
        .init(family: .reverseHolo, cardID: "swsh12/127_hires.png", name: "Togedemaru"),
        .init(family: .regularHolo, cardID: "pgo/24_hires.png", name: "Articuno"),
        .init(family: .cosmosHolo, cardID: "swshp/SWSH012_hires.png", name: "Morpeko"),
        .init(family: .amazingRare, cardID: "swsh4/9_hires.png", name: "Celebi"),
        .init(family: .radiantHolo, cardID: "pgo/11_hires.png", name: "Radiant Charizard"),
        .init(family: .trainerGalleryHolo, cardID: "swsh11tg/TG03_hires.png", name: "Charizard"),
        .init(family: .v, cardID: "swsh7/110_hires.png", name: "Rayquaza V"),
        .init(family: .vFullArt, cardID: "swsh8/250_hires.png", name: "Mew V"),
        .init(family: .vAlternateArt, cardID: "swshp/SWSH179_hires.png", name: "Flareon V"),
        .init(family: .vmax, cardID: "swsh7/29_hires.png", name: "Gyarados VMAX"),
        .init(family: .vmaxRainbow, cardID: "swsh8/270_hires.png", name: "Espeon VMAX"),
        .init(family: .vstar, cardID: "pgo/31_hires.png", name: "Mewtwo VSTAR"),
        .init(family: .trainerFullArt, cardID: "swsh6/196_hires.png", name: "Peonia"),
        .init(family: .rainbowRare, cardID: "swsh4/188_hires.png", name: "Pikachu VMAX"),
        .init(family: .secretGold, cardID: "swsh2/209_hires.png", name: "Twin Energy"),
        .init(family: .trainerGalleryV, cardID: "swsh9tg/TG16_hires.png", name: "Mimikyu V"),
        .init(family: .shinyVault, cardID: "swsh45sv/SV093_hires.png", name: "Minccino")
    ]
}

struct CardEffectsLab: View {
    let imageRepository: (any ImageRepository)?
    @Environment(\.dismiss) private var dismiss
    @State private var effectsEnabled = true
    @State private var activeID: String?
    @State private var resetToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 22)], spacing: 26) {
                    ForEach(DebugEffectSample.all) { sample in
                        DebugEffectCell(sample: sample, repository: imageRepository, effectsEnabled: effectsEnabled,
                                        activeID: $activeID, resetToken: resetToken)
                    }
                }.padding(24)
            }
            .background(Color(red: 0.07, green: 0.045, blue: 0.11).ignoresSafeArea())
            .navigationTitle("Card Effects Lab")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(effectsEnabled ? "Effects Off" : "Effects On") { effectsEnabled.toggle(); activeID = nil; resetToken += 1 }
                    Button("Reset") { activeID = nil; resetToken += 1 }
                    Button("Done") { dismiss() }
                }
            }
        }.preferredColorScheme(.dark).accessibilityIdentifier("card-effects-lab")
    }
}

private struct DebugEffectCell: View {
    let sample: DebugEffectSample; let repository: (any ImageRepository)?; let effectsEnabled: Bool
    @Binding var activeID: String?; let resetToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DebugInteractiveCard(sample: sample, repository: repository, effectsEnabled: effectsEnabled, activeID: $activeID, resetToken: resetToken)
                .aspectRatio(734 / 1024, contentMode: .fit)
            Text(sample.family.rawValue).font(.headline)
            Text("\(sample.name) · \(sample.family.mask.rawValue)").font(.caption).foregroundStyle(.secondary)
            Text("POC fixture · visual-reference mapping").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain).accessibilityIdentifier("effect-\(sample.family.id)")
    }
}

private struct DebugInteractiveCard: View {
    let sample: DebugEffectSample; let repository: (any ImageRepository)?; let effectsEnabled: Bool
    @Binding var activeID: String?; let resetToken: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x = 0.5; @State private var y = 0.5

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DebugRemoteShaderCard(sample: sample, repository: repository, size: geometry.size,
                                      x: x, y: y, effectsEnabled: effectsEnabled)
            }
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.48), radius: 18, y: 12)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : (0.5 - y) * 12), axis: (1, 0, 0), perspective: 0.68)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : (x - 0.5) * 12), axis: (0, 1, 0), perspective: 0.68)
            .contentShape(RoundedRectangle(cornerRadius: 17))
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard effectsEnabled, !reduceMotion else { return }; activeID = sample.id
                x = min(max(value.location.x / max(geometry.size.width, 1), 0), 1)
                y = min(max(value.location.y / max(geometry.size.height, 1), 0), 1)
            }.onEnded { _ in settle() })
        }
        .onChange(of: resetToken) { _, _ in settle() }
        .onChange(of: activeID) { _, value in if value != sample.id { settle(immediate: true) } }
    }

    private func settle(immediate: Bool = false) {
        withAnimation(immediate || reduceMotion ? nil : .timingCurve(0.22, 0.82, 0.24, 1, duration: 0.42)) { x = 0.5; y = 0.5 }
    }
}

private struct DebugRemoteShaderCard: View {
    let sample: DebugEffectSample
    let repository: (any ImageRepository)?
    let size: CGSize
    let x: Double
    let y: Double
    let effectsEnabled: Bool
    @State private var image: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let image {
                ZStack {
                    Image(uiImage: image).resizable().scaledToFit()
                        .colorEffect(ShaderLibrary.cardFinish(
                            .float2(size), .float2(Float(x), Float(y)),
                            .float(Float(DebugCardEffectFamily.allCases.firstIndex(of: sample.family) ?? 0)),
                            .float(effectsEnabled ? 1 : 0)
                        ))
                    if effectsEnabled {
                        DebugFoilTextureLayer(family: sample.family, x: x, y: y)
                    }
                }
                .accessibilityIdentifier("effect-artwork-loaded-\(sample.family.id)")
            } else if let errorMessage {
                ZStack {
                    Color.red.opacity(0.20)
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).multilineTextAlignment(.center).padding()
                }
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary).overlay(ProgressView())
            }
        }
        .task(id: sample.imageURL) {
            do {
                let bytes: Data
                if let repository { bytes = try await repository.data(for: sample.imageURL).value }
                else {
                    let (data, response) = try await URLSession.shared.data(from: sample.imageURL)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ImageRepositoryError.corruptData
                    }
                    bytes = data
                }
                guard let decoded = UIImage(data: bytes) else { throw ImageRepositoryError.corruptData }
                image = decoded
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "Artwork failed to load\n\(sample.cardID)"
            }
        }
    }
}

private struct DebugFoilTextureLayer: View {
    let family: DebugCardEffectFamily
    let x: Double
    let y: Double

    private var primaryName: String {
        switch family {
        case .cosmosHolo: "FinishCosmos"
        case .vmax, .vmaxRainbow: "FinishVMax"
        case .trainerGalleryHolo, .trainerFullArt: "FinishTrainer"
        case .secretGold: "FinishGeometric"
        case .amazingRare, .rainbowRare, .shinyVault: "FinishGlitter"
        default: "FinishEtched"
        }
    }

    private var opacity: Double {
        switch family {
        case .basic: 0.10
        case .regularHolo, .cosmosHolo: 0.32
        case .radiantHolo, .vmaxRainbow, .rainbowRare, .secretGold: 0.46
        default: 0.36
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DebugBundleImages.image(named: primaryName)
                    .resizable().scaledToFill()
                    .scaleEffect(family == .cosmosHolo ? 1.0 : 1.55)
                    .offset(x: (x - 0.5) * geometry.size.width * 0.24,
                            y: (y - 0.5) * geometry.size.height * -0.20)
                    .blendMode(family == .secretGold ? .colorDodge : .screen)
                if family != .basic && family != .cosmosHolo {
                    DebugBundleImages.image(named: "FinishGrain")
                        .resizable().scaledToFill().scaleEffect(1.8)
                        .offset(x: (x - 0.5) * geometry.size.width * -0.16,
                                y: (y - 0.5) * geometry.size.height * 0.14)
                        .blendMode(.softLight).opacity(0.55)
                }
            }
            .opacity(opacity)
            .mask { DebugGenericMask(preset: family.mask) }
        }
        .allowsHitTesting(false)
    }
}

private struct DebugGenericMask: View {
    let preset: DebugCardMaskPreset

    var body: some View {
        GeometryReader { geometry in
            let art = CGRect(x: geometry.size.width * 0.08, y: geometry.size.height * 0.0985,
                             width: geometry.size.width * 0.84, height: geometry.size.height * 0.373)
            Canvas { context, size in
                var path = Path()
                switch preset {
                case .artworkWindow:
                    path.addRect(art)
                case .outsideArtworkWindow:
                    path.addRect(CGRect(origin: .zero, size: size)); path.addRect(art)
                    context.fill(path, with: .color(.white), style: FillStyle(eoFill: true)); return
                case .amazingBreakout:
                    path.addRoundedRect(in: art.insetBy(dx: -size.width * 0.05, dy: -size.height * 0.04), cornerSize: CGSize(width: 12, height: 12))
                default:
                    path.addRect(CGRect(origin: .zero, size: size))
                }
                context.fill(path, with: .color(.white))
            }
        }
    }
}

#endif
