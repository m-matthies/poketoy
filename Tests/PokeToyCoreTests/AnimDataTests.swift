import Foundation
import Testing
@testable import PokeToyCore

@Suite struct AnimDataTests {
    let xml = """
    <?xml version="1.0" ?>
    <AnimData>
      <ShadowSize>1</ShadowSize>
      <Anims>
        <Anim>
          <Name>Walk</Name><Index>0</Index>
          <FrameWidth>32</FrameWidth><FrameHeight>40</FrameHeight>
          <Durations><Duration>8</Duration><Duration>10</Duration></Durations>
        </Anim>
        <Anim>
          <Name>Attack</Name><Index>1</Index>
          <FrameWidth>80</FrameWidth><FrameHeight>80</FrameHeight>
          <RushFrame>1</RushFrame>
          <Durations><Duration>2</Duration><Duration>4</Duration><Duration>1</Duration></Durations>
        </Anim>
        <Anim><Name>Strike</Name><Index>2</Index><CopyOf>Attack</CopyOf></Anim>
        <Anim><Name>Dance</Name><CopyOf>Shake</CopyOf></Anim>
        <Anim><Name>Shake</Name><CopyOf>Attack</CopyOf></Anim>
        <Anim><Name>Loop1</Name><CopyOf>Loop2</CopyOf></Anim>
        <Anim><Name>Loop2</Name><CopyOf>Loop1</CopyOf></Anim>
        <Anim><Name>Dangling</Name><CopyOf>Nope</CopyOf></Anim>
      </Anims>
    </AnimData>
    """

    @Test func parsesPlainAnimations() throws {
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(data.anims["Walk"] == AnimInfo(name: "Walk", frameWidth: 32, frameHeight: 40, durations: [8, 10], sourceName: "Walk"))
        #expect(data.anims["Attack"]?.durations == [2, 4, 1])
    }

    @Test func resolvesCopyOfChains() throws {
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(data.anims["Strike"] == AnimInfo(name: "Strike", frameWidth: 80, frameHeight: 80, durations: [2, 4, 1], sourceName: "Attack"))
        #expect(data.anims["Dance"]?.sourceName == "Attack")
    }

    @Test func dropsCyclesAndDanglingCopies() throws {
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(data.anims["Loop1"] == nil)
        #expect(data.anims["Loop2"] == nil)
        #expect(data.anims["Dangling"] == nil)
    }

    @Test func resolveReturnsFirstAvailableCandidate() throws {
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(data.resolve(["Sleep", "Walk", "Attack"])?.name == "Walk")
        #expect(data.resolve(["Sleep", "Hop"]) == nil)
    }

    @Test func rejectsMalformedXML() {
        #expect(throws: AnimDataError.self) { try AnimData(xml: Data("<AnimData><Anims>".utf8)) }
        #expect(throws: AnimDataError.self) { try AnimData(xml: Data("<AnimData><Anims></Anims></AnimData>".utf8)) }
    }
}
