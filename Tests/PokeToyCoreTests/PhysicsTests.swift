import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PhysicsTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    var floor: Surface { Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor) }
    var shelf: Surface { Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window) }
    var world: World { World(screens: [screen], surfaces: [floor, shelf]) }

    func simulate(_ body: inout Body, seconds: Double, world: World) {
        for _ in 0..<Int(seconds * 60) { Physics.step(&body, dt: 1.0 / 60, world: world) }
    }

    @Test func fallsAndLandsOnFloor() {
        var body = Body(position: CGPoint(x: 800, y: 400))
        simulate(&body, seconds: 2, world: world)
        #expect(body.surfaceID == -1)
        #expect(body.position.y == 50)
        #expect(body.velocity == .zero)
    }

    @Test func landsOnHighestSurfaceBelow() {
        var body = Body(position: CGPoint(x: 450, y: 400))
        simulate(&body, seconds: 2, world: world)
        #expect(body.surfaceID == 7)
        #expect(body.position.y == 250)
    }

    @Test func passesThroughSurfacesWhileRising() {
        var body = Body(position: CGPoint(x: 450, y: 100), velocity: CGVector(dx: 0, dy: 1200))
        for _ in 0..<12 { Physics.step(&body, dt: 1.0 / 60, world: world) }
        #expect(body.position.y > 250)
        #expect(!body.isGrounded)
    }

    @Test func walksAlongAndOffASurface() {
        var body = Body(position: CGPoint(x: 590, y: 250), velocity: CGVector(dx: 70, dy: 0), surfaceID: 7)
        Physics.step(&body, dt: 1.0 / 60, world: world)
        #expect(body.isGrounded)
        #expect(body.position.x > 590)
        simulate(&body, seconds: 0.5, world: world)
        #expect(body.position.x > 600)
        #expect(body.surfaceID != 7)
    }

    @Test func ridesMovingSurface() {
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        let moved = World(screens: [screen], surfaces: [floor, Surface(id: 7, minX: 320, maxX: 620, y: 290, kind: .window)])
        Physics.step(&body, dt: 1.0 / 60, world: moved)
        #expect(body.surfaceID == 7)
        #expect(body.position.y == 290)
    }

    @Test func fallsWhenSurfaceVanishes() {
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        let closed = World(screens: [screen], surfaces: [floor])
        Physics.step(&body, dt: 1.0 / 60, world: closed)
        #expect(!body.isGrounded)
        simulate(&body, seconds: 1, world: closed)
        #expect(body.surfaceID == -1)
    }

    @Test func bouncesOffScreenSide() {
        var body = Body(position: CGPoint(x: 995, y: 400), velocity: CGVector(dx: 900, dy: 0))
        Physics.step(&body, dt: 1.0 / 60, world: world)
        #expect(body.position.x <= 1000)
        #expect(body.velocity.dx < 0)
    }

    @Test func limitsFallSpeed() {
        var body = Body(position: CGPoint(x: 800, y: 100_000))
        simulate(&body, seconds: 3, world: World(screens: [screen], surfaces: []))
        #expect(body.velocity.dy >= -Physics.terminalVelocity)
    }

    @Test func bouncesOffScreenSideWhileAboveTheScreen() {
        var body = Body(position: CGPoint(x: 995, y: 900), velocity: CGVector(dx: 900, dy: 0))
        Physics.step(&body, dt: 1.0 / 60, world: world)
        #expect(body.position.x <= 1000)
        #expect(body.velocity.dx < 0)
    }

    @Test func thrownUpwardComesBackDown() {
        var body = Body(position: CGPoint(x: 800, y: 700), velocity: CGVector(dx: 0, dy: 1500))
        for _ in 0..<(3 * 60) {
            Physics.step(&body, dt: 1.0 / 60, world: world)
            #expect(world.isRecoverable(body.position, margin: 200))
        }
        #expect(body.surfaceID == -1)
    }

    @Test func ridesWindowMovingSideways() {
        let before = World(screens: [screen], surfaces: [floor, shelf], windowOrigins: [7: 300])
        var body = Body(position: CGPoint(x: 450, y: 260))
        simulate(&body, seconds: 0.5, world: before)
        #expect(body.surfaceID == 7)
        let moved = World(screens: [screen],
                          surfaces: [floor, Surface(id: 7, minX: 350, maxX: 650, y: 250, kind: .window)],
                          windowOrigins: [7: 350])
        Physics.step(&body, dt: 1.0 / 60, world: moved)
        #expect(body.surfaceID == 7)
        #expect(abs(body.position.x - 500) < 0.001)
    }
}
