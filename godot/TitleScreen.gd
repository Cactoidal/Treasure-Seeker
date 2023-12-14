extends Control

var user_address
var user_balance = "0"

var zama_rpc = "https://devnet.zama.ai"
var req_header = "Content-Type: application/json"
var chain_id = 8009
var chain_public_key

var box_public_key
var box_secret_key
var box_key_calldata

var test_contract = "0x3e1fE0a71765411A638E096bC84a62498277F63e"

var signed_data = ""

var gas_balance_check_timer = 0

var tx_count 
var gas_price
var confirmation_timer = 0
var tx_function_name = ""
var tx_parameter = ["None"]

var camera

var player
var game_board = load("res://Field.tscn")
var press_space_text = load("res://PressSpace.png")
var waiting_for_opponent_text = load("res://WaitingForOpponent.png")

var queueable = false
var in_queue = false
var check_for_opponent_timer = 0
var opponent

var debug_menu
var debug_menu_open = false

func _ready():
	debug_menu = get_parent().get_node("DebugMenu")
	camera = get_parent().get_node("Camera")
	check_keystore()
	get_address()
	get_balance()
	$GetZAMA.connect("pressed", self, "open_faucet_confirm")
	$FaucetBackground/CopyAddress.connect("pressed", self, "copy_address")
	$FaucetBackground/Confirm.connect("pressed", self, "open_faucet")
	
	
	debug_menu.get_node("Copy").connect("pressed", self, "copy_address")
	debug_menu.get_node("Close").connect("pressed", self, "close_debug_menu")
	debug_menu.get_node("Faucet").connect("pressed", self, "debug_open_faucet")
	debug_menu.get_node("ExitQueue").connect("pressed", self, "start_transaction", ["debug_exit_queue"])
	debug_menu.get_node("EndGame").connect("pressed", self, "start_transaction", ["stop_mining"])
	debug_menu.get_node("ForceEnd").connect("pressed", self, "start_transaction", ["debug_force_end"])
	

	
	

var pending_action
var fadeout = false
var fadepause = 0
var fadein = false
var exiting = false

var check_opponent_trap_timer = false
var check_opponent_end_game_timer = false

func _process(delta):
	if fadeout == true:
		$Fadeout.modulate.a += delta
		if $Fadeout.modulate.a >= 1:
			fadeout = false
			fadepause = 0.1
	if fadepause > 0:
		fadepause -= delta
		if fadepause <= 0:
			fadepause = 0
			call(pending_action)
	if fadein == true:
		$Fadeout.modulate.a -= delta
		if $Fadeout.modulate.a <= 0:
			exiting = false
			fadein = false
			
			
	if gas_balance_check_timer > 0:
		gas_balance_check_timer -= delta
		if gas_balance_check_timer < 0:
			get_balance()
			gas_balance_check_timer = 12
	
	if check_for_opponent_timer > 0:
		check_for_opponent_timer -= delta
		if check_for_opponent_timer < 0:
			check_for_opponent()
			check_for_opponent_timer = 10
	
	if check_mining_timer > 0:
		check_mining_timer -= delta
		if check_mining_timer < 0:
			check_mining_timer = 4
			if player.started_mining == false:
				check_mining_status(user_address)
			else:
				check_mining_status(player.opponent)
	
	if check_ending_timer > 0:
		check_ending_timer -= delta
		if check_ending_timer < 0:
			check_ending_timer = 4
			if player.game_ended == false:
				check_ending_status(user_address)
			else:
				check_ending_status(player.opponent)
	
	if Input.is_action_just_pressed("action") && queueable == true && in_queue == false:
		in_queue = true
		get_parent().get_node("PressSpace").texture = waiting_for_opponent_text
		
		start_transaction("join_match")
		check_for_opponent_timer = 10
	
	if Input.is_action_just_pressed("debug"):
		if debug_menu_open == false:
			debug_menu_open = true
			get_parent().get_node("DebugMenu").visible = true
		else:
			debug_menu_open = false
			get_parent().get_node("DebugMenu").visible = false
	

func check_keystore():
	var file = File.new()
	if file.file_exists("user://keystore") != true:
		var bytekey = Crypto.new()
		var content = bytekey.generate_random_bytes(32)
		file.open("user://keystore", File.WRITE)
		file.store_buffer(content)
		file.close()

func get_address():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	user_address = Fhe.get_address(content)
	$FaucetBackground/Address.text = user_address
	debug_menu.get_node("Address").text = user_address
	file.close()

func open_faucet_confirm():
	$GetZAMA.visible = false
	$FaucetBackground.visible = true

func open_faucet():
	gas_balance_check_timer = 12
	OS.shell_open("https://faucet.zama.ai")

func copy_address():
	OS.set_clipboard(user_address)

func fade(action):
	if exiting == false:
		exiting = true
		pending_action = action
		fadeout = true

func start_game():
	var new_game = game_board.instance()
	add_child(new_game)
	move_child(new_game, 0)
	player = new_game.get_node("Player")
	player.ethers = self
	player.opponent = opponent
	new_game.get_node("Camera").make_current()
	get_parent().get_node("Moon").visible = false
	get_parent().get_node("Title").visible = false
	get_parent().get_node("PressSpace").visible = false
	fadein = true

var check_mining_timer = 0
func wait_for_mining():
	track_score()
	player.ui.get_node("TrapPhase").visible = false
	check_mining_timer = 4

var check_ending_timer = 0
func wait_for_game_end():
	get_parent().get_node("Moon").visible = true
	get_parent().get_node("Title").visible = true
	get_parent().get_node("PressSpace").visible = true
	get_parent().get_node("PressSpace").texture = press_space_text
	check_ending_timer = 4


func start_transaction(function_name, param=["None"]):
	tx_function_name = function_name
	tx_parameter = param
	get_tx_count()

var http_request_delete_tx_write
var http_request_delete_tx_read
var http_request_delete_balance
var http_request_delete_count
var http_request_delete_gas


func get_balance():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_balance = http_request
	http_request.connect("request_completed", self, "get_balance_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_getBalance", "params": [user_address, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_balance_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		if get_result["result"].hex_to_int() > 0:
			queueable = true
			camera.press_space_timer = 3.3
			$GetZAMA.visible = false
			$FaucetBackground.visible = false
			gas_balance_check_timer = 0
		else:
			$GetZAMA.visible = true
			
		var balance = String(get_result["result"].hex_to_int())
		user_balance = balance
		debug_menu.get_node("Balance").text = balance
	else:
		pass
	http_request_delete_balance.queue_free()
	
	
	
func check_for_opponent():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "check_for_opponent_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = Fhe.get_opponent(content, chain_id, test_contract, zama_rpc)
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": test_contract, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func check_for_opponent_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	if response_code == 200:
		print(get_result)
		var _opponent = Fhe.decode_address(get_result["result"])
		if _opponent != "0x0000000000000000000000000000000000000000":
			opponent = _opponent
			check_for_opponent_timer = 0
			fade("start_game")
			
		
	http_request_delete_tx_write.queue_free()


func check_mining_status(var player_address):
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "check_mining_status_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = Fhe.get_mining_status(content, chain_id, test_contract, zama_rpc, player_address)
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": test_contract, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func check_mining_status_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	if response_code == 200:
		print(get_result)
		var status = Fhe.decode_bool(get_result["result"])
		if status == "true":
			if player.started_mining == false:
				player.started_mining = true
			else:
				check_mining_timer = 0
				player.start_mining()
				fadein = true
		
	


func check_ending_status(var player_address):
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "check_ending_status_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = Fhe.get_ending_status(content, chain_id, test_contract, zama_rpc, player_address)
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": test_contract, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func check_ending_status_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	if response_code == 200:
		print(get_result)
		var status = Fhe.decode_bool(get_result["result"])
		if status == "false":
			if player.game_ended == false:
				player.game_ended = true
			else:
				check_ending_timer = 0
				player.conclude_game()


func get_tx_count():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_count = http_request
	http_request.connect("request_completed", self, "get_tx_count_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_getTransactionCount", "params": [user_address, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_tx_count_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	print(get_result["result"].hex_to_int())
	if response_code == 200:
		var count = get_result["result"].hex_to_int()
		tx_count = count
	else:
		pass
	http_request_delete_count.queue_free()
	estimate_gas()


func estimate_gas():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_gas = http_request
	http_request.connect("request_completed", self, "estimate_gas_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_gasPrice", "params": [], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func estimate_gas_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	if response_code == 200:
		var estimate = get_result["result"].hex_to_int()
		gas_price = int(float(estimate) * 1.12)
	else:
		pass
	http_request_delete_gas.queue_free()
	call(tx_function_name)
	
	
func join_match():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	Fhe.join_match(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, self)

func try_mine():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	Fhe.try_mine(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, tx_parameter, self)
	
func stop_mining():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	Fhe.stop_mining(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, self)

func get_chain_public_key():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "get_chain_public_key_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"from": null, "to":"0x000000000000000000000000000000000000005d","data":"0xd9d47bb001"}, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_chain_public_key_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	if response_code == 200:
		var file = File.new()
		file.open("user://keystore", File.READ)
		var content = file.get_buffer(32)
		file.close()
		
		var chain_public_key = get_result["result"]
		var trap1 = tx_parameter[0]
		var trap2 = tx_parameter[1]
		var trap3 = tx_parameter[2]
		
		Fhe.set_traps(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, chain_public_key, trap1, trap2, trap3, self)
		
	
	else:
		print("no")
		pass
		
	


func track_score():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	
	Fhe.track_score(content, chain_id, test_contract, zama_rpc, self)

func get_current_score():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "get_current_score_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = box_key_calldata
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": test_contract, "from": user_address, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_current_score_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	if response_code == 200:
		var secret = get_result["result"]
		var number = Fhe.decode_crypto_box(box_public_key, box_secret_key, secret)
		player.handle_score(number)
	





# Called from Rust
func set_box_keys(var _public_key, var _secret_key, var _calldata):
	box_public_key = _public_key
	box_secret_key = _secret_key
	box_key_calldata = _calldata
	get_current_score()

	
	

	
func set_signed_data(var signature):
	
	var signed_data = "".join(["0x", signature])
	#print(signed_data)
	
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "send_transaction_attempted")

	var tx = {"jsonrpc": "2.0", "method": "eth_sendRawTransaction", "params": [signed_data], "id": 7}

	var error = http_request.request(zama_rpc, 
	[req_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))



func send_transaction_attempted(result, response_code, headers, body):
	var get_result = parse_json(body.get_string_from_ascii())

	print(get_result)

	if response_code == 200:
		pass
	else:
		pass
	
	http_request_delete_tx_write.queue_free()





#   DEBUG FUNCTIONS   #

func close_debug_menu():
	debug_menu_open = false
	get_parent().get_node("DebugMenu").visible = false

func debug_open_faucet():
	OS.shell_open("https://faucet.zama.ai")

func debug_exit_queue():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	Fhe.exit_queue(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, self)

func debug_force_end():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	Fhe.force_end(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, self)
