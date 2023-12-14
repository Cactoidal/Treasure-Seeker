extends MeshInstance

var tile_number

var already_used = false

var player
var activated = false
var stay_visible = false

func _ready():
	pass # Replace with function body.

var oscillate_timer = 0
var oscillate_down = true
func _process(delta):
	if oscillate_timer > 0:
		oscillate_timer -= delta
		if oscillate_down == true:
			get_surface_material(0).albedo.a -= delta
		else:
			get_surface_material(0).albedo.a += delta
		if oscillate_timer < 0:
			oscillate_timer = 1.2
			if oscillate_down == true:
				oscillate_down = false
			else:
				oscillate_down = true


func set_trap():
	if activated == true && already_used == false:
		already_used = true
		player.trapped_tiles.push_back(self)
		stay_visible = true
		player.ui.get_node("TrapPhase/TrapsCount").text = "Traps Set:\n" + String(player.trapped_tiles.size()) + " / 3"

func try_mine():
	if activated == true && already_used == false:
		already_used = true
		stay_visible = true
		player.ui.get_node("MinePhase/MineTimer").visible = true
		player.mine_wait_timer = 9
		player.ethers.start_transaction("try_mine", tile_number)
		player.follow_up_mine(self)
		oscillate_timer = 1.2

func success():
	oscillate_timer = 0
	get_surface_material(0).albedo = Color(0,1,0,0.75)

func hit_trap():
	oscillate_timer = 0
	get_surface_material(0).albedo = Color(1,0,0,0.75)


func _on_Area_body_entered(body):
	visible = true
	player = body
	player.current_tile = self
	activated = true


func _on_Area_body_exited(body):
	if stay_visible == false:
		visible = false
	activated = false
