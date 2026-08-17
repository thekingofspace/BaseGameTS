//-------------------------------------------------------------------- SERVICES
import { RunService, Workspace } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Blackbox from "@shared/Blackbox";
import { BP_BuildableWall } from "@game/Classes/Structure/BP_BuildableWall";
//-------------------------------------------------------------------- Topline VARS
const Log = Blackbox.Get("Test.Wall")

const Pillar_Size = new Vector3(4, 12, 4)
const Pillar_Color = Color3.fromRGB(190, 190, 190)

const Chain_Origin = new Vector3(0, 6, 0)
const Chain_Spacing = 25
const Chain_Count = 4

const Hub_Origin = new Vector3(0, 6, 120)
const Hub_Radius = 18
const Hub_Spokes = 5

const Settle = 0.35

const Run_Teardown_Phases = true
//-------------------------------------------------------------------- Builders
function MakePillar(Name: string): Model {
    const Body = new Instance("Part")
    Body.Name = "Body"
    Body.Size = Pillar_Size
    Body.Anchored = true
    Body.Color = Pillar_Color
    Body.Material = Enum.Material.Concrete

    const Shell = new Instance("Model")
    Shell.Name = Name
    Body.Parent = Shell
    Shell.PrimaryPart = Body

    return Shell
}

function SpawnWall(Name: string, Position: Vector3): BP_BuildableWall {
    const Wall = BP_BuildableWall.New()

    Wall.RegisterModel(MakePillar(Name), new CFrame(Position))

    return Wall
}

function SegmentCount(): number {
    const Folder = Workspace.FindFirstChild("WallSegments")

    return Folder !== undefined ? Folder.GetChildren().size() : 0
}

function ReportLinks(Label: string, Walls: Array<BP_BuildableWall>) {
    let Total = 0

    for (const Wall of Walls) {
        Total += Wall.LinkCount()
    }

    Log.Info(Label, {
        walls: Walls.size(),
        linkEnds: Total,
        segmentParts: SegmentCount(),
        built: Walls.filter((Wall) => Wall.IsBuilt).size()
    })
}

function WaitForBuilds(Walls: Array<BP_BuildableWall>, Budget: number): boolean {
    const Deadline = os.clock() + Budget

    while (os.clock() < Deadline) {
        let Pending = 0

        for (const Wall of Walls) {
            if (!Wall.IsBuilt && !Wall.Destroyed) {
                Pending += 1
            }
        }

        if (Pending === 0) {
            return true
        }

        task.wait(0.1)
    }

    return false
}
//-------------------------------------------------------------------- Test run
if (RunService.IsStudio()) {
    task.spawn(() => {
        Log.Info("wall test starting")

        const Chain = new Array<BP_BuildableWall>()

        for (let Index = 0; Index < Chain_Count; Index++) {
            Chain.push(SpawnWall(`ChainWall_${Index}`, Chain_Origin.add(new Vector3(Index * Chain_Spacing, 0, 0))))
            task.wait(Settle)
        }

        ReportLinks("chain spawned, mid-build", Chain)

        if (!WaitForBuilds(Chain, 15)) {
            Log.Warn("chain did not finish building in time")
        }

        ReportLinks("chain built", Chain)

        const Head = Chain[0]
        Log.Info("chain head", {
            name: Head.ClassName,
            isA_BP_Structure: Head.IsA("BP_Structure"),
            isA_MonoBehaviour: Head.IsA("MonoBehaviour"),
            guid: Head.GetGUID(),
            links: Head.LinkCount(),
            walls: Head.GetWalls().size(),
            farthest: Head.FarthestLinkDistance(),
            enabledAfterBuild: Head.Enabled
        })

        const Hub = new Array<BP_BuildableWall>()
        Hub.push(SpawnWall("HubWall_Center", Hub_Origin))
        task.wait(Settle)

        for (let Index = 0; Index < Hub_Spokes; Index++) {
            const Angle = (Index / Hub_Spokes) * math.pi * 2
            const Offset = new Vector3(math.cos(Angle) * Hub_Radius, 0, math.sin(Angle) * Hub_Radius)

            Hub.push(SpawnWall(`HubWall_${Index}`, Hub_Origin.add(Offset)))
            task.wait(Settle)
        }

        WaitForBuilds(Hub, 15)

        const Center = Hub[0]
        Log.Info("hub cap check", {
            maxLinks: Center.MaxLinks,
            centerLinks: Center.LinkCount(),
            withinCap: Center.OutboundCount() <= Center.MaxLinks,
            centerOutbound: Center.OutboundCount(),
            segmentParts: SegmentCount()
        })

        if (!Run_Teardown_Phases) {
            Log.Info("wall test done, layout frozen", {
                segmentParts: SegmentCount(),
                activeBehaviours: BP_BuildableWall.ActiveCount()
            })

            return
        }

        const Victim = Chain[1]
        const VictimLinks = Victim.LinkCount()
        const SegmentsBefore = SegmentCount()

        Victim.Destroy()
        task.wait(Victim.FadeTime + 0.6)

        Log.Info("destroy", {
            victimLinks: VictimLinks,
            destroyed: Victim.Destroyed,
            segmentsBefore: SegmentsBefore,
            segmentsAfter: SegmentCount(),
            neighbourLinks: Chain[0].LinkCount() + Chain[2].LinkCount()
        })

        const Survivors = Chain.filter((Wall) => !Wall.Destroyed)
        ReportLinks("chain after destroy", Survivors)

        const Replacement = SpawnWall("ChainWall_1_Replacement", Chain_Origin.add(new Vector3(Chain_Spacing, 0, 0)))
        WaitForBuilds([Replacement], 15)
        task.wait(Settle)

        Log.Info("replacement relinked", {
            links: Replacement.LinkCount(),
            outbound: Replacement.OutboundCount(),
            neighbourLinks: Chain[0].LinkCount() + Chain[2].LinkCount(),
            segmentParts: SegmentCount()
        })

        const BeforeRelink = Center.LinkCount()
        Center.Relink()
        task.wait(Settle)

        Log.Info("relink is destructive by design", {
            before: BeforeRelink,
            after: Center.LinkCount(),
            note: "drops every segment it touches then re-links using its own outbound budget"
        })

        Log.Info("wall test done", { activeBehaviours: BP_BuildableWall.ActiveCount() })
    })
}
