class_name GateView extends Node3D

const PANEL_WIDTH := Gate.HALF_WIDTH * 2.0
const PANEL_HEIGHT := 2.0
const PANEL_THICKNESS := 0.1
const LABEL_HEIGHT := PANEL_HEIGHT + 0.3

const GOOD_COLOR := Color(0.25, 0.75, 0.3)
const BAD_COLOR := Color(0.8, 0.25, 0.25)
const NEUTRAL_COLOR := Color(0.55, 0.55, 0.6)

var _panels: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _slot_gates: Array[Gate] = []
var _mesh: BoxMesh

func _ready() -> void:
    _mesh = BoxMesh.new()
    _mesh.size = Vector3(PANEL_WIDTH, PANEL_HEIGHT, PANEL_THICKNESS)

func render(gates: Gates) -> void:
    _ensure(gates.pairs.size() * 2)
    var i := 0
    for pair in gates.pairs:
        _place(i, pair.left, pair.y)
        i += 1
        _place(i, pair.right, pair.y)
        i += 1
    for j in range(i, _panels.size()):
        _panels[j].visible = false
        _labels[j].visible = false

func _place(i: int, gate: Gate, y: float) -> void:
    _panels[i].visible = true
    _labels[i].visible = true
    _panels[i].position = Vector3(gate.x_centre, PANEL_HEIGHT * 0.5, y)
    _labels[i].position = Vector3(gate.x_centre, LABEL_HEIGHT, y)
    if _slot_gates[i] != gate:
        _slot_gates[i] = gate
        _labels[i].text = _label_text(gate)
        var material := _panels[i].material_override as StandardMaterial3D
        material.albedo_color = _color_for(gate)

func _color_for(gate: Gate) -> Color:
    if gate.op == Gate.Op.SET_FORMATION:
        return NEUTRAL_COLOR
    return GOOD_COLOR if gate.is_good() else BAD_COLOR

func _label_text(gate: Gate) -> String:
    match gate.op:
        Gate.Op.ADD:
            return "%+d" % int(gate.value)
        Gate.Op.MUL:
            return "x%.1f" % gate.value
        Gate.Op.TIER_STEP:
            return "WEAPON %+d" % int(gate.value)
        _:
            return Formation.Kind.find_key(int(gate.value))

func _ensure(n: int) -> void:
    while _panels.size() < n:
        var material := StandardMaterial3D.new()
        var panel := MeshInstance3D.new()
        panel.mesh = _mesh
        panel.material_override = material
        add_child(panel)
        _panels.append(panel)

        var label := Label3D.new()
        label.font_size = 64
        label.pixel_size = 0.008
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        add_child(label)
        _labels.append(label)

        _slot_gates.append(null)
