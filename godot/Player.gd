extends KinematicBody

var ethers

var speed = 7
const ACCEL_DEFAULT = 7
const ACCEL_AIR = 1
onready var accel = ACCEL_DEFAULT
var gravity = 9.8
var jump = 5

var cam_accel = 40
var mouse_sense = 0.1
var snap

var direction = Vector3()
var velocity = Vector3()
var gravity_vec = Vector3()
var movement = Vector3()

var ui
var tiles
var current_tile
var trap_phase = true
var mine_phase = false

var trapped_tiles = []

var mine_wait_timer = 0

var started_mining = false
var stopped_mining = false

var game_ended = false

var start_pos

var opponent

var current_score = 0
var displayed_score = 0



func _ready():
	start_pos = global_transform.origin
	ui = get_parent().get_node("UI")
	tiles = get_parent().get_node("Plateau/Tiles")
	current_tile = tiles.get_children()[0]
	var tile_number = 0
	for tile in tiles.get_children():
		tile.tile_number = tile_number
		tile_number += 1
	
	ui.get_node("TrapPhase/SetTraps").connect("pressed", self, "set_traps")
	ui.get_node("TrapPhase/Revert").connect("pressed", self, "revert_traps")
	ui.get_node("MinePhase/StopMining").connect("pressed", self, "stop_mining")
	ui.get_node("Overlay/StopMining").connect("pressed", self, "stop_mining")
		
func _physics_process(delta):
	if global_transform.origin.y < -20:
		global_transform.origin = start_pos
		gravity_vec[1] /= 2
		
	if mine_wait_timer > 0:
		mine_wait_timer -= delta
		ui.get_node("MinePhase/MineTimer").text = String(mine_wait_timer)
		if mine_wait_timer < 0:
			ui.get_node("MinePhase/MineTimer").visible = false
			mine_wait_timer = 0
	#get keyboard input
	direction = Vector3.ZERO
	var h_rot = global_transform.basis.get_euler().y
	var f_input = Input.get_action_strength("down") - Input.get_action_strength("up")
	var h_input = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction = Vector3(h_input, 0, f_input).rotated(Vector3.UP, h_rot).normalized()
	
	#jumping and gravity
	if is_on_floor():
		snap = -get_floor_normal()
		accel = ACCEL_DEFAULT
		gravity_vec = Vector3.ZERO
	else:
		snap = Vector3.DOWN
		accel = ACCEL_AIR
		gravity_vec += Vector3.DOWN * gravity * delta
		
#	if Input.is_action_just_pressed("jump") and is_on_floor():
#		snap = Vector3.ZERO
#		gravity_vec = Vector3.UP * jump

	if Input.is_action_just_pressed("action"):
		if trap_phase == true && trapped_tiles.size() < 3:
			current_tile.set_trap()
		elif mine_phase == true && mine_wait_timer == 0:
			current_tile.try_mine()
	
	#make it move
	velocity = velocity.linear_interpolate(direction * speed, accel * delta)
	movement = velocity + gravity_vec
	
	move_and_slide_with_snap(movement, snap, Vector3.UP)

var check_score_timer = 2
func _process(delta):
	if pending_miners.size() > 0:
		check_score_timer -= delta
		if check_score_timer < 0:
			check_score_timer = 4
			ethers.track_score()
	else:
		check_score_timer = 4
	
func set_traps():
	if trapped_tiles.size() == 3:
		trap_phase = false
		var trap1 = trapped_tiles[0].tile_number
		var trap2 = trapped_tiles[1].tile_number
		var trap3 = trapped_tiles[2].tile_number
		
		ethers.start_transaction("get_chain_public_key", [trap1,trap2,trap3])
		print([trap1,trap2,trap3])
		trapped_tiles = []
		ethers.get_node("Fadeout/Background").visible = true
		ethers.get_node("Fadeout/Background/Waiting").visible = true
		ethers.fade("wait_for_mining")

func start_mining():
	ethers.get_node("Fadeout/Background/Waiting").visible = false
	ethers.get_node("Fadeout/Background").visible = false
	mine_phase = true
	ui.get_node("MinePhase").visible = true
	for tile in tiles.get_children():
		tile.already_used = false
		tile.stay_visible = false
		tile.visible = false
		if tile == current_tile && tile.activated == true:
			tile.visible = true

func revert_traps():
	for trap in trapped_tiles:
		trap.stay_visible = false
		trap.already_used = false
		trap.visible = false
		if trap == current_tile && trap.activated == true:
			trap.visible = true
	trapped_tiles = []
	ui.get_node("TrapPhase/TrapsCount").text = "Traps Set:\n0 / 3"
	

var pending_miners = []
func follow_up_mine(var tile):
	pending_miners.push_back(tile)

var mine_id = 1
var score_obtained = false
func handle_score(var new_score):
	print("Turn " + String(mine_id) + "\n")
	mine_id += 1
	print("Current score: " + String(current_score) + "\n")
	print("New score: " + String(new_score) + "\n")
	
	if new_score == 0 && score_obtained == true:
		print("rpc error")
		return
	if current_score == 0:
		current_score = new_score
		score_obtained = true
	else:
		if new_score > current_score:
			#survived
			current_score = new_score
			displayed_score += 1
			ui.get_node("MinePhase/Score").text = "Your score:\n" + String(displayed_score)
			if pending_miners.size() > 0:
				pending_miners[0].success()
				pending_miners.erase(pending_miners[0])
		elif new_score < current_score:
			#ded
			mine_phase = false
			displayed_score = 0
			for tile in tiles.get_children():
				tile.trapped()
			pending_miners = []
			hit_trap()

func hit_trap():
	mine_wait_timer = 0
	ui.get_node("MinePhase").visible = false
	ui.get_node("Overlay").visible = true
	ui.get_node("Overlay/StopMining").visible = true


func stop_mining():
	if mine_wait_timer == 0 && stopped_mining == false:
		stopped_mining = true
		ethers.start_transaction("stop_mining")
		mine_phase = false
		ui.get_node("Overlay").visible = false
		ui.get_node("Overlay/StopMining").visible = false
		ui.get_node("MinePhase").visible = false
		ethers.get_node("Fadeout/Background").visible = true
		ethers.get_node("Fadeout/Background/Waiting").visible = true
		ethers.fade("wait_for_game_end")


func conclude_game():
	print("hello")
	ethers.get_node("Fadeout/Background/Waiting").visible = false
	ethers.get_node("Fadeout/Background").visible = false
	ethers.camera.make_current()
	ethers.fadein = true
	ethers.in_queue = false
	ethers.player = null
	get_parent().queue_free()
