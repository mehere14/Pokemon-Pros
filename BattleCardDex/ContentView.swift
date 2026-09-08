import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @ObservedObject var model: CatalogViewModel

    init(model: CatalogViewModel) { self.model = model }

    var body: some View {
#if DEBUG
        if let mode = ProcessInfo.processInfo.environment[DevelopmentCloudKitProbe.launchEnvironmentKey],
           [DevelopmentCloudKitProbe.readMode, DevelopmentCloudKitProbe.mutationDenialMode].contains(mode) {
            DevelopmentCloudKitProbeView(mode: mode)
        } else {
            CatalogHomeView(model: model)
        }
#else
        CatalogHomeView(model: model)
#endif
    }
}

private struct CatalogHomeView: View {
    @ObservedObject var model: CatalogViewModel
    @AppStorage("appearance") private var appearance = "dark"
    @State private var query = ""
    @State private var generation: String?
    @State private var type: String?
    @State private var showFilters = false
    @State private var selected: CreatureSummary?
    @State private var lastSelectedCreatureID: Int?
    @State private var launcherScrollPosition: Int?
    @State private var shuffleSeed = 0
    @State private var sparkleRotation = 0.0
#if DEBUG
    @State private var showCardEffectsLab = false
#endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedCreatureID: Int?

    private let design = DesignConstants.standard

    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "system": nil; default: .dark }
    }

    private var filteredCreatures: [CreatureSummary] {
        let filter = CreatureFilter(query: query, generation: generation, type: type)
        return shuffleSeed == 0
            ? filter.apply(to: model.creatures)
            : filter.surpriseOrder(model.creatures, seed: UInt64(shuffleSeed))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ElectricBackground()
                Group {
                    switch model.state {
                    case .loading: LoadingStateView()
                    case .emptyInstall: ServiceStateView(title: "Catalog warming up", message: "The shared catalog is ready to download.", action: "Try Again") { Task { await model.retry() } }
                    case .offline: ServiceStateView(title: "Catalog unavailable", message: "Connect to the internet, then try again.", action: "Retry") { Task { await model.retry() } }
                    case .incompatibleSchema: ServiceStateView(title: "Catalog update required", message: "This version cannot read the published catalog yet.", action: "Retry") { Task { await model.retry() } }
                    case .ready, .stale: launcher
                    }
                }
            }
            .preferredColorScheme(colorScheme)
            .task { await model.load() }
            .sheet(isPresented: $showFilters) {
                FilterPanel(query: $query, generation: $generation, type: $type, availableGenerations: model.creatures.compactMap(\.generation), availableTypes: model.creatures.flatMap(\.types))
                    .presentationDetents([.medium, .large])
            }
#if DEBUG
            .fullScreenCover(isPresented: $showCardEffectsLab) {
                CardEffectsLab(imageRepository: model.imageRepository)
            }
#endif
            .fullScreenCover(item: $selected, onDismiss: {
                guard let lastSelectedCreatureID else { return }
                launcherScrollPosition = lastSelectedCreatureID
                focusedCreatureID = lastSelectedCreatureID
            }) { creature in
                MockupCreatureDetailView(creature: creature,
                                         allCreatures: filteredCreatures,
                                         profile: model.profile(for: creature.id),
                                         cards: model.cards(for: creature.id),
                                         evolutions: model.evolutions,
                                         allProfiles: model.profiles,
                                         allCards: model.cards,
                                         imageRepository: model.imageRepository,
                                         onCreatureChange: { id in
                                             Task { await model.loadDetails(for: detailPrefetchIDs(around: id)) }
                                         })
            }
        }
    }

    private var launcher: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: design.spacing.medium) {
                    header
                    regionFilter
                    if filteredCreatures.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try a different name, number, or filter."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        let columnCount = geometry.size.width >= 700 ? design.layout.largeLayoutColumns : design.layout.phonePortraitColumns
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: design.spacing.small), count: columnCount), spacing: design.spacing.small) {
                            ForEach(filteredCreatures) { creature in
                                Button {
                                    lastSelectedCreatureID = creature.id
                                    selected = creature
                                    Task { await model.loadDetails(for: [creature.id]) }
                                } label: {
                                    CreatureTile(creature: creature, imageRepository: model.imageRepository)
                                }
                                .buttonStyle(.plain)
                                .id(creature.id)
                                .accessibilityFocused($focusedCreatureID, equals: creature.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, geometry.size.width >= 700 ? design.spacing.largeLayoutMargin : design.spacing.phoneMargin)
                .padding(.top, design.spacing.base)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $launcherScrollPosition)
            .refreshable { await model.retry() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: design.spacing.small) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BATTLE CARD DEX").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Color(design.palette.secondary))
                Text("Choose Your Battler").font(.largeTitle.bold()).foregroundStyle(Color(design.palette.text))
                Text("A focused field guide for the shared catalog.").font(.subheadline).foregroundStyle(Color(design.palette.mutedText))
            }
            HStack(spacing: 8) {
#if DEBUG
                Button { showCardEffectsLab = true } label: {
                    Label("Card Effects Lab", systemImage: "sparkles.rectangle.stack")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 42)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card-effects-lab-cta")
#endif
                IconButton(systemName: "magnifyingglass", label: "Search and filter") { showFilters = true }
                IconButton(systemName: "sparkles", label: "Surprise me", rotation: sparkleRotation) {
                    withAnimation(.easeInOut(duration: reduceMotion ? MotionConstants.standard.reducedMotionDuration : MotionConstants.standard.shuffleDuration)) {
                        shuffleSeed = Int.random(in: 1...Int.max)
                        sparkleRotation += 180
                    }
                }
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                } label: {
                    Image(systemName: "circle.lefthalf.filled").frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(Color(design.palette.secondary))
                .accessibilityLabel("Appearance")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var regionFilter: some View {
        Button { showFilters = true } label: {
            HStack {
                Image(systemName: "globe.americas.fill")
                Text("FIRST \(model.creatures.count) • FILTERS")
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(design.palette.text))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(design.palette.outline).opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens local name, number, generation, and type filters")
    }

    private func detailPrefetchIDs(around id: Int) -> [Int] {
        guard let index = filteredCreatures.firstIndex(where: { $0.id == id }) else { return [id] }
        return [index - 1, index, index + 1]
            .filter(filteredCreatures.indices.contains)
            .map { filteredCreatures[$0].id }
    }

}

private struct CreatureTile: View {
    let creature: CreatureSummary
    let imageRepository: (any ImageRepository)?
    private let design = DesignConstants.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: design.shape.largeRadius)
                    .fill(LinearGradient(colors: [Color(design.palette.surfaceHigh), Color(design.palette.surfaceLowest)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = creature.artworkURL {
                    CatalogImageView(url: url, repository: imageRepository, placeholderID: creature.id)
                        .scaledToFit().padding(14)
                } else { TilePlaceholder(id: creature.id) }
                VStack { HStack { Spacer(); Text(String(format: "%03d", creature.id)).font(.caption2.monospacedDigit()).foregroundStyle(Color(design.palette.mutedText)) }; Spacer() }.padding(10)
            }
            .aspectRatio(0.86, contentMode: .fit)
            Text(creature.displayName).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Color(design.palette.text)).lineLimit(1)
            HStack(spacing: 5) { ForEach(creature.types.prefix(2), id: \.self) { TypeChip(name: $0) } }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: design.shape.largeRadius))
        .overlay(RoundedRectangle(cornerRadius: design.shape.largeRadius).stroke(Color(design.palette.outline).opacity(0.25)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(creature.displayName), number \(creature.id)")
        .accessibilityHint("Opens creature details")
    }
}

private struct TilePlaceholder: View {
    let id: Int
    private let design = DesignConstants.standard
    var body: some View {
        ZStack { Circle().fill(Color(design.palette.outline)).frame(width: 74, height: 74); Text(String(format: "%02d", id)).font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(Color(design.palette.text).opacity(0.85)) }
    }
}

private struct CreatureDetailView: View {
    let creature: CreatureSummary
    let allCreatures: [CreatureSummary]
    let profile: CreatureProfile?
    let cards: [BattleCardDetail]
    let evolutions: [Int: EvolutionChain]
    let allProfiles: [Int: CreatureProfile]
    let allCards: [BattleCardDetail]
    let imageRepository: (any ImageRepository)?
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false
    @State private var showEvolution = false
    @State private var showCards = false
    @State private var dragOffset: CGFloat = 0
    @State private var currentIndex: Int
    @State private var currentCreature: CreatureSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let design = DesignConstants.standard

    init(creature: CreatureSummary,
         allCreatures: [CreatureSummary],
         profile: CreatureProfile?,
         cards: [BattleCardDetail],
         evolutions: [Int: EvolutionChain] = [:],
         allProfiles: [Int: CreatureProfile] = [:],
         allCards: [BattleCardDetail] = [],
         imageRepository: (any ImageRepository)? = nil) {
        self.creature = creature
        self.allCreatures = allCreatures
        self.profile = profile
        self.cards = cards
        self.evolutions = evolutions
        self.allProfiles = allProfiles
        self.allCards = allCards
        self.imageRepository = imageRepository
        let index = allCreatures.firstIndex(of: creature) ?? 0
        _currentIndex = State(initialValue: index)
        _currentCreature = State(initialValue: creature)
    }

    private var currentProfile: CreatureProfile? { allProfiles[currentCreature.id] ?? profile }
    private var currentCards: [BattleCardDetail] {
        let filtered = allCards.filter { $0.summary.relatedCreatureIDs.contains(currentCreature.id) }
        return filtered.isEmpty && currentCreature.id == creature.id ? cards : filtered
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ElectricBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            Button("Done") { dismiss() }.buttonStyle(.bordered).tint(Color(design.palette.primary))
                            Spacer()
                            Text(String(format: "%03d", currentCreature.id)).font(.caption.monospacedDigit()).foregroundStyle(Color(design.palette.mutedText))
                            Button { moveCarousel(by: -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous creature")
                            Button { moveCarousel(by: 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next creature")
                        }.padding(.horizontal)
                        artwork
                        VStack(alignment: .leading, spacing: 8) {
                            Text(currentCreature.displayName).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Color(design.palette.text))
                            HStack { ForEach(currentCreature.types, id: \.self) { TypeChip(name: $0) }; Spacer(); Text(currentCreature.generation?.uppercased() ?? "FIELD GUIDE").font(.caption2.weight(.bold)).foregroundStyle(Color(design.palette.mutedText)) }
                        }.padding(.horizontal)
                        HStack(spacing: 10) {
                            ActionTile(title: "Field Guide", icon: "book.closed.fill") { showGuide = true }
                            ActionTile(title: "Evolution", icon: "arrow.triangle.branch") { showEvolution = true }
                            ActionTile(title: "Cards", icon: "rectangle.stack.fill") { showCards = true }
                        }.padding(.horizontal)
                        stats
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showGuide) { EncyclopediaView(profile: currentProfile) }
            .sheet(isPresented: $showEvolution) {
                EvolutionPanel(creature: currentCreature,
                               allCreatures: allCreatures,
                               chain: evolutions.values.first(where: { $0.memberIDs.contains(currentCreature.id) }),
                               onSelect: { id in
                                   guard let index = allCreatures.firstIndex(where: { $0.id == id }) else { return }
                                   moveCarousel(by: index - currentIndex)
                               })
            }
            .sheet(isPresented: $showCards) { RelatedCardsPanel(creature: currentCreature, cards: currentCards, imageRepository: imageRepository) }
            .gesture(carouselGesture)
            .task(id: currentCreature.id) { prefetchAdjacentArtwork() }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                settleCarouselImmediately()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Creature details for \(currentCreature.displayName)")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: moveCarousel(by: 1); case .decrement: moveCarousel(by: -1); @unknown default: break }
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [Color(design.palette.tertiary).opacity(0.5), Color(design.palette.surfaceLowest)], startPoint: .top, endPoint: .bottom))
            if let url = currentCreature.artworkURL {
                CatalogImageView(url: url, repository: imageRepository, placeholderID: currentCreature.id)
                    .scaledToFit().padding(26)
            } else { TilePlaceholder(id: currentCreature.id) }
        }
        .frame(maxWidth: 460).aspectRatio(1.1, contentMode: .fit).padding(.horizontal)
        .offset(x: dragOffset)
        .scaleEffect(1 - min(abs(dragOffset) / 700, 0.06))
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CORE DATA").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Color(design.palette.primary))
            HStack { DataPoint(label: "HEIGHT", value: currentProfile?.heightMetres.map { String(format: "%.1fm", $0) } ?? "—"); DataPoint(label: "WEIGHT", value: currentProfile?.weightKilograms.map { String(format: "%.1fkg", $0) } ?? "—"); DataPoint(label: "MOVES", value: String(currentProfile?.moves.count ?? 0)) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal)
    }

    private var carouselGesture: some Gesture {
        DragGesture(minimumDistance: 6).onChanged { value in
            guard !reduceMotion else { return }
            dragOffset = value.translation.width * InteractionConstants.standard.carouselFingerTravelMultiplier
        }.onEnded { value in
            guard !reduceMotion else { return }
            let model = CarouselInteractionModel(constants: .standard)
            let durationEstimate = abs(value.predictedEndTranslation.width - value.translation.width) > 34 ? 0.2 : 0.5
            switch model.decide(translation: value.translation.width, duration: durationEstimate, index: currentIndex, count: allCreatures.count, width: 390) {
            case .move(let delta): moveCarousel(by: delta)
            case .boundary: bumpAtBoundary(for: value.translation.width)
            case .stay: withAnimation(.easeOut(duration: MotionConstants.standard.carouselDuration)) { dragOffset = 0 }
            }
        }
    }

    private func moveCarousel(by delta: Int) {
        let next = currentIndex + delta
        guard allCreatures.indices.contains(next) else {
            bumpAtBoundary(for: delta > 0 ? -1 : 1)
            return
        }
        guard !reduceMotion else {
            currentIndex = next
            currentCreature = allCreatures[next]
            dragOffset = 0
            return
        }
        let direction = delta > 0 ? -1.0 : 1.0
        withAnimation(.easeOut(duration: MotionConstants.standard.carouselDuration)) { dragOffset = direction * 600 }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionConstants.standard.carouselDuration) {
            currentIndex = next
            currentCreature = allCreatures[next]
            dragOffset = 0
        }
    }

    private func bumpAtBoundary(for travel: CGFloat) {
        guard !reduceMotion else { dragOffset = 0; return }
        withAnimation(.easeOut(duration: MotionConstants.standard.boundaryBumpDuration)) {
            dragOffset = travel > 0 ? 18 : -18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionConstants.standard.boundaryBumpDuration) {
            withAnimation(.easeOut(duration: MotionConstants.standard.boundaryBumpDuration)) { dragOffset = 0 }
        }
    }

    private func settleCarouselImmediately() {
        guard dragOffset != 0 else { return }
        withTransaction(Transaction(animation: nil)) { dragOffset = 0 }
    }

    private func prefetchAdjacentArtwork() {
        guard let imageRepository else { return }
        let nearbyURLs = [currentIndex - 1, currentIndex + 1]
            .compactMap { allCreatures.indices.contains($0) ? allCreatures[$0].artworkURL : nil }
        guard !nearbyURLs.isEmpty else { return }
        Task {
            for url in nearbyURLs {
                _ = try? await imageRepository.data(for: url)
            }
        }
    }
}

private struct EncyclopediaView: View {
    let profile: CreatureProfile?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let profile {
                    Section("Overview") { if let genus = profile.genus { Text(genus) }; if let description = profile.description { Text(description) }; LabeledContent("Base experience", value: profile.baseExperience.map(String.init) ?? "—") }
                    Section("Abilities") { ForEach(profile.abilities + profile.hiddenAbilities, id: \.self) { Text($0) } }
                    Section("Moves") { ForEach(profile.moves) { Text($0.displayName) } }
                    Section("Encounters") { ForEach(Array(profile.encounters.enumerated()), id: \.offset) { _, encounter in Text(encounter.location) } }
                } else { ContentUnavailableView("Field guide unavailable", systemImage: "book.closed", description: Text("This section will appear after the catalog is refreshed.")) }
            }
            .navigationTitle("Field Guide")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct EvolutionPanel: View {
    let creature: CreatureSummary
    let allCreatures: [CreatureSummary]
    let chain: EvolutionChain?
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Capsule().fill(.secondary).frame(width: 44, height: 5).padding(.top, 8)
                Text("EVOLUTION PATH").font(.caption.weight(.bold)).tracking(1.4)
                if let chain {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        EvolutionNodeView(
                            node: chain.root,
                            currentID: creature.id,
                            names: Dictionary(uniqueKeysWithValues: allCreatures.map { ($0.id, $0.displayName) }),
                            onSelect: { id in
                                dismiss()
                                onSelect(id)
                            }
                        )
                            .padding()
                            .accessibilityHint("Choose a creature to return to its details")
                    }
                } else {
                    ContentUnavailableView("No evolution data", systemImage: "arrow.triangle.branch", description: Text("This catalog entry has no published evolution chain."))
                }
                Spacer()
            }
            .navigationTitle("Evolution")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.fraction(0.42), .large])
        .presentationBackground(.ultraThinMaterial)
        .gesture(DragGesture().onEnded { value in
            let decision = PanelInteractionModel(constants: .standard)
                .closingDecision(travel: max(0, value.translation.height), extent: 400)
            if !reduceMotion && decision == .close { dismiss() }
        })
    }
}

private struct EvolutionNodeView: View {
    let node: EvolutionNode
    let currentID: Int
    let names: [Int: String]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            EvolutionNodeChip(id: node.creatureID, name: names[node.creatureID] ?? node.name, isCurrent: node.creatureID == currentID, onSelect: onSelect)
            if !node.children.isEmpty {
                Rectangle().fill(.secondary.opacity(0.35)).frame(width: 2, height: 18)
                HStack(alignment: .top, spacing: 20) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        VStack(spacing: 6) {
                            if let requirement = child.requirements.first {
                                Text(requirement.label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 100)
                            }
                            EvolutionNodeView(node: child, currentID: currentID, names: names, onSelect: onSelect)
                        }
                    }
                }
            }
        }
    }
}

private struct EvolutionNodeChip: View {
    let id: Int
    let name: String
    let isCurrent: Bool
    let onSelect: (Int) -> Void
    var body: some View {
        Button {
            onSelect(id)
        } label: {
            VStack(spacing: 4) {
            TilePlaceholder(id: id).frame(width: 66, height: 66).background(.thinMaterial, in: Circle())
            Text(name).font(.caption.weight(.semibold)).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(isCurrent ? Color.orange.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isCurrent ? Color.orange : Color.secondary.opacity(0.24), lineWidth: isCurrent ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), index \(id)\(isCurrent ? ", current" : "")")
        .accessibilityHint("Shows this creature in the carousel")
    }
}

private extension EvolutionRequirement {
    var label: String {
        if let minimumLevel { return "Level \(minimumLevel)" }
        if let item { return item }
        if let trigger { return trigger }
        if let timeOfDay { return timeOfDay }
        return "Requirement"
    }
}

private struct RelatedCardsPanel: View {
    let creature: CreatureSummary
    let cards: [BattleCardDetail]
    let imageRepository: (any ImageRepository)?
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BattleCardDetail?
    @State private var lastSelectedCardID: String?
    @AccessibilityFocusState private var focusedCardID: String?
    var body: some View {
        NavigationStack {
            Group { if cards.isEmpty { ContentUnavailableView("No related cards yet", systemImage: "rectangle.stack", description: Text("Cards appear when this catalog entry has related records.")) } else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(cards) { card in Button {
                lastSelectedCardID = card.id
                selected = card
            } label: {
                CardTile(card: card, imageRepository: imageRepository)
            }
            .buttonStyle(.plain)
            .accessibilityFocused($focusedCardID, equals: card.id)
            .accessibilityHint("Opens the full card detail")
            } }.padding() } } }
            .navigationTitle("Related Cards")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected, onDismiss: { focusedCardID = lastSelectedCardID }) { CardViewer(card: $0, imageRepository: imageRepository) }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CardTile: View {
    let card: BattleCardDetail
    let imageRepository: (any ImageRepository)?
    var body: some View { VStack(alignment: .leading) {
        if let url = card.summary.smallImageURL {
            CatalogImageView(url: url, repository: imageRepository, placeholderID: nil)
                .aspectRatio(0.72, contentMode: .fit)
        } else {
            Rectangle().fill(.quaternary).aspectRatio(0.72, contentMode: .fit)
                .overlay(Text(card.summary.name.prefix(1)).font(.largeTitle.bold()))
        }
        Text(card.summary.name).font(.caption.weight(.semibold))
        Text("\(card.summary.setName) • \(card.summary.collectorNumber)").font(.caption2).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine).accessibilityLabel("\(card.summary.name), \(card.summary.setName), \(card.summary.collectorNumber)") }
}

private struct CardViewer: View {
    let card: BattleCardDetail
    let imageRepository: (any ImageRepository)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
        if let url = card.summary.largeImageURL {
            CatalogImageView(url: url, repository: imageRepository, placeholderID: nil)
                .aspectRatio(0.72, contentMode: .fit)
        } else {
            Rectangle().fill(.quaternary).aspectRatio(0.72, contentMode: .fit)
                .overlay(Text(card.summary.name).font(.title.bold()).multilineTextAlignment(.center).padding())
        }
        Text(card.summary.name).font(.title.bold())
        LabeledContent("Set", value: card.summary.setName)
        LabeledContent("Collector number", value: card.summary.collectorNumber)
        if let rarity = card.summary.rarity { LabeledContent("Rarity", value: rarity) }
        if !card.summary.types.isEmpty { LabeledContent("Type", value: card.summary.types.joined(separator: ", ")) }
        if let hp = card.summary.hitPoints { LabeledContent("HP", value: String(hp)) }
        ForEach(card.rules, id: \.self) { Text($0).font(.body) }
    }
    .padding()
    .opacity(isPresented ? 1 : 0)
    .offset(y: isPresented ? 0 : 24)
    .scaleEffect(isPresented ? 1 : 0.82)
    .onAppear {
        guard !isPresented else { return }
        withAnimation(.easeOut(duration: reduceMotion ? MotionConstants.standard.reducedMotionDuration : 0.340)) {
            isPresented = true
        }
    }
    }.navigationTitle("Card Detail").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
}

private struct FilterPanel: View {
    @Binding var query: String
    @Binding var generation: String?
    @Binding var type: String?
    let availableGenerations: [String]
    let availableTypes: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { Form { Section("Search") { TextField("Name or number", text: $query).textInputAutocapitalization(.never) }; Section("Generation") { Picker("Generation", selection: Binding(get: { generation ?? "all" }, set: { generation = $0 == "all" ? nil : $0 })) { Text("All").tag("all"); ForEach(Set(availableGenerations).sorted(), id: \.self) { Text($0).tag($0) } } }; Section("Type") { Picker("Type", selection: Binding(get: { type ?? "all" }, set: { type = $0 == "all" ? nil : $0 })) { Text("All").tag("all"); ForEach(Set(availableTypes).sorted(), id: \.self) { Text($0).tag($0) } } }; Section { Button("Clear Filters") { query = ""; generation = nil; type = nil } } }.navigationTitle("Search & Filters").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
}

private struct DataPoint: View { let label: String; let value: String; var body: some View { VStack(alignment: .leading) { Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary); Text(value).font(.headline.monospacedDigit()) }.frame(maxWidth: .infinity, alignment: .leading) } }
private struct TypeChip: View { let name: String; var body: some View { Text(name.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 4).background(Color.orange.opacity(0.28), in: Capsule()).foregroundStyle(.orange) } }
private struct ActionTile: View { let title: String; let icon: String; let action: () -> Void; var body: some View { Button(action: action) { Label(title, systemImage: icon).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) } }
private struct IconButton: View { let systemName: String; let label: String; let rotation: Double; let action: () -> Void; init(systemName: String, label: String, rotation: Double = 0, action: @escaping () -> Void) { self.systemName = systemName; self.label = label; self.rotation = rotation; self.action = action }; var body: some View { Button(action: action) { Label(label, systemImage: systemName).labelStyle(.iconOnly).rotationEffect(.degrees(rotation)).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(label) } }
private struct ElectricBackground: View { private let design = DesignConstants.standard; var body: some View { LinearGradient(colors: [Color(design.palette.background), Color(design.palette.surfaceLowest)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea().overlay(alignment: .topTrailing) { Circle().fill(Color(design.palette.tertiary).opacity(0.18)).frame(width: 240, height: 240).blur(radius: 30).offset(x: 70, y: -80) } } }
private struct LoadingStateView: View { var body: some View { ProgressView("Loading catalog…").tint(.yellow).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) } }
private struct ServiceStateView: View { let title: String; let message: String; let action: String; let retry: () -> Void; var body: some View { ContentUnavailableView { Label(title, systemImage: "icloud.slash") } description: { Text(message) } actions: { Button(action) { retry() }.buttonStyle(.borderedProminent) }.frame(maxWidth: .infinity, maxHeight: .infinity) } }

struct CatalogImageView: View {
    let url: URL
    let repository: (any ImageRepository)?
    let placeholderID: Int?
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image { image.resizable() }
            else if failed { placeholder }
            else { placeholder.overlay(ProgressView().controlSize(.small)) }
        }
        .task(id: url) {
            guard let repository else { failed = true; return }
            do {
                let bytes = try await repository.data(for: url).value
#if canImport(UIKit)
                guard let uiImage = UIImage(data: bytes) else { failed = true; return }
                image = Image(uiImage: uiImage)
#else
                failed = true
#endif
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let placeholderID { TilePlaceholder(id: placeholderID) }
        else { RoundedRectangle(cornerRadius: 12).fill(.quaternary).overlay(Image(systemName: "rectangle.portrait")) }
    }
}

private enum DetailPanel: Equatable {
    case cards
    case evolution
}

private struct EvolutionStage: Identifiable {
    let id: Int
    let name: String
    let requirement: String?
}

private struct MockupCreatureDetailView: View {
    let creature: CreatureSummary
    let allCreatures: [CreatureSummary]
    let profile: CreatureProfile?
    let cards: [BattleCardDetail]
    let evolutions: [Int: EvolutionChain]
    let allProfiles: [Int: CreatureProfile]
    let allCards: [BattleCardDetail]
    let imageRepository: (any ImageRepository)?
    let onCreatureChange: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentIndex: Int
    @State private var currentCreature: CreatureSummary
    @State private var horizontalDrag: CGFloat = 0
    @State private var verticalDrag: CGFloat = 0
    @State private var candidatePanel: DetailPanel?
    @State private var activePanel: DetailPanel?
    @State private var closingDrag: CGFloat = 0
    @State private var showGuide = false
    @State private var selectedCard: BattleCardDetail?

    private let design = DesignConstants.standard

    init(creature: CreatureSummary,
         allCreatures: [CreatureSummary],
         profile: CreatureProfile?,
         cards: [BattleCardDetail],
         evolutions: [Int: EvolutionChain],
         allProfiles: [Int: CreatureProfile],
         allCards: [BattleCardDetail],
         imageRepository: (any ImageRepository)?,
         onCreatureChange: @escaping (Int) -> Void) {
        self.creature = creature
        self.allCreatures = allCreatures
        self.profile = profile
        self.cards = cards
        self.evolutions = evolutions
        self.allProfiles = allProfiles
        self.allCards = allCards
        self.imageRepository = imageRepository
        self.onCreatureChange = onCreatureChange
        let index = allCreatures.firstIndex(of: creature) ?? 0
        _currentIndex = State(initialValue: index)
        _currentCreature = State(initialValue: creature)
    }

    private var currentProfile: CreatureProfile? { allProfiles[currentCreature.id] ?? profile }
    private var currentCards: [BattleCardDetail] {
        let matches = allCards.filter { $0.summary.relatedCreatureIDs.contains(currentCreature.id) }
        return matches.isEmpty && currentCreature.id == creature.id ? cards : matches
    }
    private var currentChain: EvolutionChain? {
        evolutions.values.first { $0.memberIDs.contains(currentCreature.id) }
    }
    private var summariesByID: [Int: CreatureSummary] {
        var values = Dictionary(uniqueKeysWithValues: allCreatures.map { ($0.id, $0) })
        allProfiles.values.forEach { values[$0.summary.id] = $0.summary }
        return values
    }

    var body: some View {
        GeometryReader { geometry in
            let isTablet = geometry.size.width >= 700
            let revealProgress = panelRevealProgress(height: geometry.size.height)

            ZStack {
                ElectricBackground()
                homeContent(size: geometry.size, isTablet: isTablet)
                    .scaleEffect(1 - revealProgress * 0.015)
                    .blur(radius: revealProgress * 6)
                    .brightness(-revealProgress * 0.12)
                    .allowsHitTesting(activePanel == nil)

                if activePanel != nil || candidatePanel != nil {
                    Color.black.opacity(0.58 * revealProgress)
                        .ignoresSafeArea()
                        .onTapGesture { closePanel() }
                        .accessibilityLabel("Close panel")
                }

                if activePanel == .cards || candidatePanel == .cards {
                    cardsPanel(size: geometry.size, isTablet: isTablet)
                }
                if activePanel == .evolution || candidatePanel == .evolution {
                    evolutionPanel(size: geometry.size, isTablet: isTablet)
                }
                if let selectedCard {
                    InteractiveCardViewer(card: selectedCard, imageRepository: imageRepository) {
                        self.selectedCard = nil
                    }
                    .zIndex(30)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(openingGesture(height: geometry.size.height))
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color(design.palette.background).ignoresSafeArea())
        .sheet(isPresented: $showGuide) { EncyclopediaView(profile: currentProfile) }
        .task(id: currentCreature.id) {
            prefetchAdjacentArtwork()
            onCreatureChange(currentCreature.id)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            settleImmediately()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Creature details for \(currentCreature.displayName)")
    }

    private func homeContent(size: CGSize, isTablet: Bool) -> some View {
        VStack(spacing: isTablet ? 16 : 10) {
            detailHeader
            panelPill(panel: .cards, direction: "Pull down", title: "Cards", icon: "chevron.down")

            if isTablet {
                HStack(spacing: size.width > size.height ? 60 : 38) {
                    artwork(size: size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    creatureCopy(isTablet: true)
                        .frame(width: min(430, size.width * 0.40), alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            } else {
                artwork(size: size).frame(maxHeight: .infinity)
                creatureCopy(isTablet: false)
            }

            pageIndicator
            panelPill(panel: .evolution, direction: "Swipe up", title: "Evolutions", icon: "chevron.up")
                .padding(.bottom, isTablet ? 18 : 10)
        }
        .padding(.horizontal, isTablet ? 46 : 18)
        .padding(.top, isTablet ? 18 : 8)
    }

    private var detailHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to all creatures")

            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color(design.palette.onPrimary))
                    .frame(width: 34, height: 34)
                    .background(Color(design.palette.primary), in: RoundedRectangle(cornerRadius: 10))
                Text("BATTLE CARD DEX")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color(design.palette.text))
            }

            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Color(design.palette.primary)).frame(width: 7, height: 7)
                    .shadow(color: Color(design.palette.primary).opacity(0.55), radius: 5)
                Text("FIRST \(allCreatures.count) · \(String(format: "%03d", currentCreature.id))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(design.palette.mutedText))
            }
        }
    }

    private func artwork(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Color(design.palette.tertiary).opacity(0.22))
                .frame(width: min(size.width * 0.48, 480))
                .blur(radius: 36)
            if let url = currentCreature.artworkURL {
                CatalogImageView(url: url, repository: imageRepository, placeholderID: currentCreature.id)
                    .scaledToFit()
                    .padding(30)
            } else {
                TilePlaceholder(id: currentCreature.id)
            }
            HStack {
                carouselButton(icon: "arrow.left", label: "Previous creature", delta: -1)
                Spacer()
                carouselButton(icon: "arrow.right", label: "Next creature", delta: 1)
            }
            .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .offset(x: horizontalDrag)
        .scaleEffect(1 - min(abs(horizontalDrag) / max(size.width, 1), InteractionConstants.standard.carouselMaximumScaleReduction))
        .gesture(carouselGesture(width: size.width))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: moveCarousel(by: 1)
            case .decrement: moveCarousel(by: -1)
            @unknown default: break
            }
        }
    }

    private func carouselButton(icon: String, label: String, delta: Int) -> some View {
        Button { moveCarousel(by: delta) } label: {
            Image(systemName: icon)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func creatureCopy(isTablet: Bool) -> some View {
        VStack(alignment: .leading, spacing: isTablet ? 15 : 8) {
            Text(String(format: "NO. %03d", currentCreature.id))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(design.palette.secondary))
            Text(currentCreature.displayName)
                .font(.system(size: isTablet ? 50 : 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(design.palette.text))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(currentCreature.types, id: \.self) { TypeChip(name: $0) }
                Text(currentProfile?.genus?.uppercased() ?? currentCreature.generation?.uppercased() ?? "FIELD GUIDE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(design.palette.mutedText))
                    .lineLimit(1)
            }
            if let description = currentProfile?.description {
                Text(description)
                    .font(.system(size: isTablet ? 16 : 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(design.palette.mutedText))
                    .lineSpacing(4)
                    .lineLimit(isTablet ? 4 : 2)
            }
            fieldGuidePanel
        }
    }

    private var fieldGuidePanel: some View {
        Button { showGuide = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("FIELD GUIDE", systemImage: "book.closed.fill")
                        .font(.caption.weight(.black)).tracking(1.2)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color(design.palette.focus)).frame(width: 6, height: 6)
                        Text("LIVE SCAN").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Color(design.palette.focus))
                }
                HStack(spacing: 14) {
                    DataPoint(label: "HEIGHT", value: currentProfile?.heightMetres.map { String(format: "%.1f m", $0) } ?? "—")
                    DataPoint(label: "WEIGHT", value: currentProfile?.weightKilograms.map { String(format: "%.1f kg", $0) } ?? "—")
                    DataPoint(label: "ABILITY", value: currentProfile?.abilities.first ?? "—")
                }
                HStack {
                    Text("Tap for full profile")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(design.palette.mutedText))
            }
            .padding(20)
            .foregroundStyle(Color(design.palette.text))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(design.palette.outline)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Field Guide")
    }

    private var pageIndicator: some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                let progress = allCreatures.count > 1
                    ? CGFloat(currentIndex) / CGFloat(allCreatures.count - 1)
                    : 1

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(design.palette.mutedText).opacity(0.32))
                    Capsule()
                        .fill(Color(design.palette.primary))
                        .frame(width: max(6, geometry.size.width * progress))
                }
                .animation(.easeOut(duration: 0.26), value: currentIndex)
            }
            .frame(width: 72, height: 6)

            Text("\(currentIndex + 1) / \(allCreatures.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(design.palette.mutedText))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Creature \(currentIndex + 1) of \(allCreatures.count)")
        .accessibilityIdentifier("creature-position-indicator")
    }

    private func panelPill(panel: DetailPanel, direction: String, title: String, icon: String) -> some View {
        Button { openPanel(panel) } label: {
            HStack(spacing: 6) {
                if panel == .evolution { Image(systemName: icon).foregroundStyle(Color(design.palette.secondary)) }
                Text(direction.uppercased()).foregroundStyle(Color(design.palette.mutedText))
                Text(title.uppercased()).fontWeight(.black).foregroundStyle(Color(design.palette.text))
                if panel == .cards { Image(systemName: icon).foregroundStyle(Color(design.palette.secondary)) }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.7)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(design.palette.outline)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }

    private func cardsPanel(size: CGSize, isTablet: Bool) -> some View {
        let height = size.height
        return VStack(alignment: .leading, spacing: 14) {
            panelHeader(eyebrow: "RELATED COLLECTION", title: "\(currentCreature.displayName) cards")
            if currentCards.isEmpty {
                ContentUnavailableView("No related cards yet", systemImage: "rectangle.stack", description: Text("Cards appear when related records are published."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: isTablet ? 4 : 2), spacing: 18) {
                        ForEach(currentCards) { card in
                            Button { selectedCard = card } label: { CardTile(card: card, imageRepository: imageRepository) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens full card detail")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            panelCloseGrip(label: "Swipe up to close", panel: .cards, extent: size.height)
        }
        .padding(.horizontal, isTablet ? 46 : 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(width: size.width, height: height, alignment: .top)
        .background(panelBackground)
        .clipShape(Rectangle())
        .offset(y: panelOffset(for: .cards, panelHeight: height))
        .frame(maxHeight: .infinity, alignment: .top)
        .transition(.move(edge: .top))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("related-cards-panel")
    }

    private func evolutionPanel(size: CGSize, isTablet: Bool) -> some View {
        let height = size.height * (isTablet ? 0.51 : 0.58)
        let stages = flattenedEvolutionStages()
        return VStack(alignment: .leading, spacing: 14) {
            panelCloseGrip(label: "Swipe down to close", panel: .evolution, extent: size.height)
            panelHeader(eyebrow: "EVOLUTION PATH", title: stages.first.map { "\($0.name) family" } ?? "Evolution path")
            if stages.isEmpty {
                ContentUnavailableView("No evolution data", systemImage: "arrow.triangle.branch", description: Text("This creature has no published evolution path."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: isTablet ? 20 : 10) {
                            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                                if index > 0 {
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(LinearGradient(colors: [Color(design.palette.primary), Color(design.palette.secondary)], startPoint: .leading, endPoint: .trailing))
                                }
                                evolutionCard(stage, isTablet: isTablet)
                            }
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Select a stage to meet that creature.")
                .font(.caption).foregroundStyle(Color(design.palette.mutedText))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, isTablet ? 46 : 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(width: size.width, height: height, alignment: .top)
        .background(panelBackground)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .offset(y: panelOffset(for: .evolution, panelHeight: height))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom))
        .accessibilityIdentifier("evolution-panel")
    }

    private var panelBackground: some View {
        LinearGradient(colors: [Color(design.palette.surfaceHigh), Color(design.palette.surfaceLowest)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) { Circle().fill(Color(design.palette.primary).opacity(0.10)).frame(width: 220).blur(radius: 44).offset(x: -70, y: -100) }
            .overlay(Rectangle().stroke(Color(design.palette.outline), lineWidth: 1))
            .shadow(color: Color(design.palette.modalShadow), radius: 34)
    }

    private func panelHeader(eyebrow: String, title: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(1.6).foregroundStyle(Color(design.palette.secondary))
                Text(title).font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(Color(design.palette.text)).lineLimit(1)
            }
            Spacer()
            Button { closePanel() } label: {
                Image(systemName: "xmark").frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close panel")
        }
    }

    private func panelCloseGrip(label: String, panel: DetailPanel, extent: CGFloat) -> some View {
        VStack(spacing: 5) {
            Capsule().fill(Color(design.palette.mutedText).opacity(0.45)).frame(width: 38, height: 4)
            Text(label.uppercased()).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Color(design.palette.mutedText))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(closingGesture(panel: panel, extent: extent))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .onTapGesture { closePanel() }
    }

    private func evolutionCard(_ stage: EvolutionStage, isTablet: Bool) -> some View {
        let summary = summariesByID[stage.id]
        return Button {
            closePanel()
            if let index = allCreatures.firstIndex(where: { $0.id == stage.id }) {
                moveCarousel(by: index - currentIndex)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let url = summary?.artworkURL {
                        CatalogImageView(url: url, repository: imageRepository, placeholderID: stage.id).scaledToFit()
                    } else {
                        TilePlaceholder(id: stage.id)
                    }
                }
                .frame(height: isTablet ? 104 : 70)
                Text(stage.name).font(.headline.weight(.bold)).lineLimit(1)
                Text(stage.requirement ?? (stage.id == currentChain?.root.creatureID ? "Base stage" : "Evolution"))
                    .font(.caption2).foregroundStyle(Color(design.palette.mutedText)).lineLimit(2)
            }
            .frame(width: isTablet ? 180 : 120)
            .padding(isTablet ? 14 : 8)
            .foregroundStyle(Color(design.palette.text))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(stage.id == currentCreature.id ? Color(design.palette.primary).opacity(0.8) : Color(design.palette.outline), lineWidth: stage.id == currentCreature.id ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.name)\(stage.id == currentCreature.id ? ", current" : "")")
    }

    private func flattenedEvolutionStages() -> [EvolutionStage] {
        guard let root = currentChain?.root else { return [] }
        var result: [EvolutionStage] = []
        func visit(_ node: EvolutionNode) {
            result.append(EvolutionStage(id: node.creatureID, name: summariesByID[node.creatureID]?.displayName ?? node.name, requirement: node.requirements.first?.label))
            node.children.forEach(visit)
        }
        visit(root)
        return result
    }

    private func panelRevealProgress(height: CGFloat) -> CGFloat {
        if activePanel != nil { return 1 }
        return min(abs(verticalDrag) / max(height * InteractionConstants.standard.panelProgressTravelFraction, 1), 1)
    }

    private func panelOffset(for panel: DetailPanel, panelHeight: CGFloat) -> CGFloat {
        if activePanel == panel {
            if panel == .cards { return min(0, closingDrag) }
            return max(0, closingDrag)
        }
        if panel == .cards { return -panelHeight + max(0, verticalDrag) }
        return panelHeight - max(0, -verticalDrag)
    }

    private func openingGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: InteractionConstants.standard.panelDirectionDetectionDistance)
            .onChanged { value in
                guard activePanel == nil,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                verticalDrag = value.translation.height
                candidatePanel = value.translation.height > 0 ? .cards : .evolution
            }
            .onEnded { value in
                guard activePanel == nil,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    resetOpeningGesture()
                    return
                }
                let direction: DetailPanel = value.translation.height > 0 ? .cards : .evolution
                let travel = abs(value.translation.height)
                if PanelInteractionModel(constants: .standard).openingDecision(travel: travel, extent: height) == .open {
                    openPanel(direction)
                } else {
                    withAnimation(panelAnimation) { resetOpeningGesture() }
                }
            }
    }

    private func closingGesture(panel: DetailPanel, extent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard activePanel == panel else { return }
                closingDrag = panel == .cards ? min(0, value.translation.height) : max(0, value.translation.height)
            }
            .onEnded { value in
                let travel = panel == .cards ? max(0, -value.translation.height) : max(0, value.translation.height)
                if PanelInteractionModel(constants: .standard).closingDecision(travel: travel, extent: extent) == .close {
                    closePanel()
                } else {
                    withAnimation(panelAnimation) { closingDrag = 0 }
                }
            }
    }

    private func openPanel(_ panel: DetailPanel) {
        withAnimation(panelAnimation) {
            candidatePanel = panel
            activePanel = panel
            verticalDrag = 0
            closingDrag = 0
        }
    }

    private func closePanel() {
        withAnimation(panelAnimation) {
            activePanel = nil
            candidatePanel = nil
            verticalDrag = 0
            closingDrag = 0
        }
    }

    private var panelAnimation: Animation {
        reduceMotion ? .linear(duration: MotionConstants.standard.reducedMotionDuration) : .timingCurve(0.2, 0.9, 0.24, 1, duration: MotionConstants.standard.panelDuration)
    }

    private func resetOpeningGesture() {
        verticalDrag = 0
        candidatePanel = nil
    }

    private func carouselGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard activePanel == nil,
                      abs(value.translation.width) > abs(value.translation.height),
                      !reduceMotion else { return }
                horizontalDrag = value.translation.width * InteractionConstants.standard.carouselFingerTravelMultiplier
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), !reduceMotion else { return }
                let durationEstimate = abs(value.predictedEndTranslation.width - value.translation.width) > InteractionConstants.standard.flickMinimumDistance ? 0.2 : 0.5
                switch CarouselInteractionModel(constants: .standard).decide(translation: value.translation.width, duration: durationEstimate, index: currentIndex, count: allCreatures.count, width: width) {
                case .move(let delta): moveCarousel(by: delta)
                case .boundary: bumpAtBoundary(for: value.translation.width)
                case .stay: withAnimation(.easeOut(duration: MotionConstants.standard.carouselDuration)) { horizontalDrag = 0 }
                }
            }
    }

    private func moveCarousel(by delta: Int) {
        let next = currentIndex + delta
        guard allCreatures.indices.contains(next) else {
            bumpAtBoundary(for: delta > 0 ? -1 : 1)
            return
        }
        if reduceMotion {
            currentIndex = next
            currentCreature = allCreatures[next]
            horizontalDrag = 0
            return
        }
        let direction = delta > 0 ? -1.0 : 1.0
        withAnimation(.timingCurve(0.22, 0.82, 0.24, 1, duration: MotionConstants.standard.carouselDuration)) { horizontalDrag = direction * 700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionConstants.standard.carouselDuration) {
            currentIndex = next
            currentCreature = allCreatures[next]
            horizontalDrag = 0
        }
    }

    private func bumpAtBoundary(for travel: CGFloat) {
        guard !reduceMotion else { horizontalDrag = 0; return }
        withAnimation(.easeOut(duration: MotionConstants.standard.boundaryBumpDuration)) { horizontalDrag = travel > 0 ? 18 : -18 }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionConstants.standard.boundaryBumpDuration) {
            withAnimation(.easeOut(duration: MotionConstants.standard.boundaryBumpDuration)) { horizontalDrag = 0 }
        }
    }

    private func prefetchAdjacentArtwork() {
        guard let imageRepository else { return }
        let urls = [currentIndex - 1, currentIndex + 1].compactMap { allCreatures.indices.contains($0) ? allCreatures[$0].artworkURL : nil }
        Task { for url in urls { _ = try? await imageRepository.data(for: url) } }
    }

    private func settleImmediately() {
        withTransaction(Transaction(animation: nil)) {
            horizontalDrag = 0
            verticalDrag = 0
            closingDrag = 0
            candidatePanel = nil
        }
    }
}

private struct InteractiveCardViewer: View {
    let card: BattleCardDetail
    let imageRepository: (any ImageRepository)?
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var tiltX = 0.0
    @State private var tiltY = 0.0
    @State private var glareX = 0.5
    @State private var glareY = 0.5

    private let design = DesignConstants.standard

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color(red: 10 / 255, green: 6 / 255, blue: 15 / 255).opacity(0.84))
                    .ignoresSafeArea()
                    .opacity(isVisible ? 1 : 0)
                    .onTapGesture { close() }

                VStack(spacing: 16) {
                    cardSurface
                        .frame(width: min(geometry.size.width * 0.40, 410))
                    Text("MOVE TO CATCH THE LIGHT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(design.palette.text).opacity(0.82))
                }
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 24)
                .scaleEffect(isVisible ? 1 : 0.82)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? MotionConstants.standard.reducedMotionDuration : 0.340)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interactive card viewer for \(card.summary.name)")
        .accessibilityIdentifier("interactive-card-viewer")
        .accessibilityAction(.escape) { close() }
    }

    private var cardSurface: some View {
        GeometryReader { cardGeometry in
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let url = card.summary.largeImageURL {
                        CatalogImageView(url: url, repository: imageRepository, placeholderID: nil)
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(colors: [Color(design.palette.secondary), Color(design.palette.tertiary), Color(design.palette.surfaceLowest)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "bolt.fill").font(.system(size: 52, weight: .black))
                                    Text(card.summary.name).font(.title.bold()).multilineTextAlignment(.center)
                                    Text("\(card.summary.setName) · \(card.summary.collectorNumber)").font(.caption.weight(.semibold))
                                }
                                .padding().foregroundStyle(.white)
                            }
                    }

                    RadialGradient(
                        colors: [.white.opacity(0.42), Color(design.palette.primary).opacity(0.12), .clear, .clear],
                        center: UnitPoint(x: glareX, y: glareY),
                        startRadius: 0,
                        endRadius: max(cardGeometry.size.width, cardGeometry.size.height) * 0.24
                    )
                    .blendMode(.screen)
                    .opacity(reduceMotion ? 0 : 0.45)
                    .allowsHitTesting(false)

                    LinearGradient(colors: [.clear, .clear, .white.opacity(0.22), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .rotationEffect(.degrees(-18))
                        .offset(x: (glareX - 0.5) * cardGeometry.size.width * 0.45,
                                y: (glareY - 0.5) * cardGeometry.size.height * 0.45)
                        .blendMode(.screen)
                        .opacity(reduceMotion ? 0 : 0.32)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.52), radius: 32, y: 24)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .gesture(tiltGesture(size: cardGeometry.size))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Interactive card surface")
                .accessibilityIdentifier("interactive-card-surface")

                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(design.palette.onPrimary))
                        .frame(width: 42, height: 42)
                        .background(Color(design.palette.primary), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.55)))
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .offset(x: 15, y: -15)
                .accessibilityLabel("Close card viewer")
            }
        }
        .aspectRatio(734 / 1024, contentMode: .fit)
    }

    private func tiltGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !reduceMotion else { return }
                let state = CardTiltInteractionModel().state(
                    locationX: value.location.x,
                    locationY: value.location.y,
                    width: size.width,
                    height: size.height
                )
                tiltX = state.rotationX
                tiltY = state.rotationY
                glareX = state.glareX
                glareY = state.glareY
            }
            .onEnded { _ in
                withAnimation(.timingCurve(0.22, 0.82, 0.24, 1, duration: MotionConstants.standard.modalReturnDuration)) {
                    tiltX = 0
                    tiltY = 0
                    glareX = 0.5
                    glareY = 0.5
                }
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: reduceMotion ? MotionConstants.standard.reducedMotionDuration : MotionConstants.standard.scrimDuration)) {
            isVisible = false
            tiltX = 0
            tiltY = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? MotionConstants.standard.reducedMotionDuration : MotionConstants.standard.scrimDuration)) {
            onClose()
        }
    }
}

private extension Color {
    init(_ color: DesignColor) {
#if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .light,
               let red = color.lightRed,
               let green = color.lightGreen,
               let blue = color.lightBlue {
                return UIColor(red: red, green: green, blue: blue, alpha: color.lightOpacity ?? color.opacity)
            }
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.opacity)
        })
#else
        self.init(red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
#endif
    }
}
