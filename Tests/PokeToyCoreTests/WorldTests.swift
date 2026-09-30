import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct WorldTests {
    // 1000x800 screen, Dock takes the bottom 50pt, menu bar the top 25pt.
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))

    @Test func screenFloorsSitAboveDockAndAtScreenBottom() {
        let world = World.build(screens: [screen], windows: [], primaryScreenHeight: 800)
        #expect(world.surfaces == [
            Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor),
            Surface(id: -2, minX: 0, maxX: 1000, y: 0, kind: .floor),
        ])
    }

    @Test func windowTopConvertsFromCoreGraphicsCoordinates() {
        let window = WindowInfo(id: 42, cgBounds: CGRect(x: 100, y: 200, width: 300, height: 400))
        let world = World.build(screens: [screen], windows: [window], primaryScreenHeight: 800)
        #expect(world.surfaces.contains(Surface(id: 42, minX: 100, maxX: 400, y: 600, kind: .window)))
    }

    @Test func windowsInFrontHideTopEdges() {
        let front = WindowInfo(id: 1, cgBounds: CGRect(x: 200, y: 100, width: 100, height: 300))  // AppKit y 400...700
        let back = WindowInfo(id: 2, cgBounds: CGRect(x: 100, y: 200, width: 400, height: 300))   // top at y 600
        let world = World.build(screens: [screen], windows: [front, back], primaryScreenHeight: 800)
        let backSurfaces = world.surfaces.filter { $0.id == 2 }
        #expect(backSurfaces == [
            Surface(id: 2, minX: 100, maxX: 200, y: 600, kind: .window),
            Surface(id: 2, minX: 300, maxX: 500, y: 600, kind: .window),
        ])
        #expect(world.surfaces.contains { $0.id == 1 && $0.y == 700 })
    }

    @Test func dropsTopsUnderTheMenuBarOrOffScreen() {
        let maximized = WindowInfo(id: 3, cgBounds: CGRect(x: 0, y: 25, width: 1000, height: 725))   // top y 775
        let offscreen = WindowInfo(id: 4, cgBounds: CGRect(x: 2000, y: 300, width: 300, height: 300))
        let world = World.build(screens: [screen], windows: [maximized, offscreen], primaryScreenHeight: 800)
        #expect(!world.surfaces.contains { $0.id == 3 || $0.id == 4 })
    }

    @Test func landingPicksHighestSurfaceCrossed() {
        let world = World(screens: [screen], surfaces: [
            Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor),
            Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window),
        ])
        #expect(world.landingSurface(x: 400, fromY: 300, toY: 0)?.id == 7)
        #expect(world.landingSurface(x: 700, fromY: 300, toY: 0)?.id == -1)
        #expect(world.landingSurface(x: 400, fromY: 240, toY: 100) == nil)
    }

    @Test func surfaceLookupByIDRequiresContainment() {
        let world = World(screens: [screen], surfaces: [Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)])
        #expect(world.surface(id: 7, containingX: 450)?.y == 250)
        #expect(world.surface(id: 7, containingX: 601) == nil)
        #expect(world.surface(id: 8, containingX: 450) == nil)
    }

    @Test func reachableSurfacesRespectRiseReachAndWidth() {
        let world = World(screens: [screen], surfaces: [
            Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor),
            Surface(id: 1, minX: 300, maxX: 600, y: 250, kind: .window),  // reachable
            Surface(id: 2, minX: 300, maxX: 600, y: 700, kind: .window),  // too high
            Surface(id: 3, minX: 950, maxX: 990, y: 200, kind: .window),  // too narrow
            Surface(id: 4, minX: 900, maxX: 1000, y: 200, kind: .window), // too far
        ])
        let reachable = world.reachableSurfaces(from: CGPoint(x: 100, y: 50), maxRise: 320, maxReach: 360, minWidth: 50)
        #expect(reachable.map(\.id) == [1])
    }

    @Test func onScreenCheck() {
        let world = World.build(screens: [screen], windows: [], primaryScreenHeight: 800)
        #expect(world.isOnAnyScreen(CGPoint(x: 500, y: 400), margin: 0))
        #expect(!world.isOnAnyScreen(CGPoint(x: 1100, y: 400), margin: 0))
        #expect(world.isOnAnyScreen(CGPoint(x: 1100, y: 400), margin: 200))
        #expect(!world.isOnAnyScreen(CGPoint(x: 500, y: -500), margin: 200))
    }

    @Test func spawnPointIsNearTopOfFirstScreen() {
        let world = World.build(screens: [screen], windows: [], primaryScreenHeight: 800)
        #expect(world.spawnPoint(fraction: 0.5) == CGPoint(x: 500, y: 765))
        #expect(World(screens: [], surfaces: []).spawnPoint(fraction: 0.5) == .zero)
    }

    @Test func recoverableWhileAboveOrBesideAScreen() {
        let world = World.build(screens: [screen], windows: [], primaryScreenHeight: 800)
        #expect(world.isRecoverable(CGPoint(x: 500, y: 1500), margin: 200))   // thrown high above
        #expect(world.isRecoverable(CGPoint(x: 1150, y: 400), margin: 200))
        #expect(!world.isRecoverable(CGPoint(x: 1300, y: 400), margin: 200))  // far off the side
        #expect(!world.isRecoverable(CGPoint(x: 500, y: -500), margin: 200))  // fell below
    }

    @Test func recordsWindowOrigins() {
        let window = WindowInfo(id: 42, cgBounds: CGRect(x: 100, y: 200, width: 300, height: 400))
        let world = World.build(screens: [screen], windows: [window], primaryScreenHeight: 800)
        #expect(world.windowOrigins[42] == 100)
    }
}
