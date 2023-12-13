extends Camera


var next_distance = 89
var terrain1 
var terrain2 
var terrain3
var sky
var sky_rotation = 90
var moon

var terrain1turn = true
var terrain2turn = false
var terrain3turn = false

var press_space
var press_space_timer = 0
var press_space_fadein = false
var press_space_fade_pause = 0
var press_space_fadeout = false


func _ready():
	terrain1 = get_parent().get_node("MeshInstance")
	terrain2 = get_parent().get_node("MeshInstance2")
	terrain3 = get_parent().get_node("MeshInstance3")
	sky = self.get_environment()
	moon = get_parent().get_node("Moon")
	press_space = get_parent().get_node("PressSpace")
	
func _process(delta):
	sky_rotation = sky.get_sky_rotation_degrees()[1]
	sky.set_sky_rotation_degrees(Vector3(0, sky_rotation+delta, 0))
	
	if moon.rect_position.y > 150:
		moon.rect_position.y -= delta/3
	
	if press_space_timer > 0:
		press_space_timer -= delta
		if press_space_timer < 0:
			press_space_timer = 0
			press_space_fadein = true
	
	if press_space_fadein == true:
		press_space.modulate.a += delta / 1.7
		if press_space.modulate.a > 1:
			press_space_fadein = false
			press_space_fadeout = true
		
	if press_space_fadeout == true:
		press_space.modulate.a -= delta / 1.7
		if press_space.modulate.a < 0:
			press_space.modulate.a = 0
			press_space_fadeout = false
			press_space_fade_pause = 0.6
	
	if press_space_fade_pause > 0:
		press_space_fade_pause -= delta
		if press_space_fade_pause < 0:
			press_space_fade_pause = 0
			press_space_fadein = true
		
		
	
	global_transform.origin.x += delta*20
	if global_transform.origin.x > next_distance:
		next_distance += 89
		if terrain1turn == true:
			terrain1.global_transform.origin.x += 267
			terrain1turn = false
			terrain2turn = true
		elif terrain2turn == true:
			terrain2.global_transform.origin.x += 267
			terrain2turn = false
			terrain3turn = true
		elif terrain3turn == true:
			terrain3.global_transform.origin.x += 267
			terrain3turn = false
			terrain1turn = true
#		global_transform.origin.x -= 100
#		terrain1.global_transform.origin.x -= 100
#		terrain2.global_transform.origin.x -= 100
