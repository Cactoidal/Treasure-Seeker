extends Control

var user_address
var user_balance = "0"

var zama_rpc = "https://devnet.zama.ai"
var req_header = "Content-Type: application/json"
var chain_id = 8009
var chain_public_key

var test_contract = "0xcA57f7b1FDfD3cbD513954938498Fe6a9bc8FF63"

var signed_data = ""

var tx_count 
var gas_price
var confirmation_timer = 0
var tx_function_name = ""
var tx_parameter = ["None"]



func _ready():
	check_keystore()
	get_address()
	get_balance()
	start_transaction("get_chain_public_key")
	

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
	$Address.text = user_address
	file.close()


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
		var balance = String(get_result["result"].hex_to_int())
		user_balance = balance
		$Balance.text = String(balance)
	else:
		pass
	http_request_delete_balance.queue_free()


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
		var encrypt_value = 17
		
		Fhe.encrypt_message(content, chain_id, test_contract, zama_rpc, gas_price, tx_count, chain_public_key, encrypt_value, self)
		
		
		
#		var bytestring = Fhe.decode_bytes(get_result["result"])
#		bytestring.erase(0,1)
#		bytestring.erase(bytestring.length()-1,1)
#		var string_array = bytestring.split(",")
#		var byte_array = []
#		for byte in string_array:
#			byte_array.push_back(int(byte))
#		chain_public_key = byte_array
#
#		var lol = Fhe.encrypt_message(chain_public_key)
#		print(lol)
		
		
		
		#print(bytestring)
		#print(Fhe.decode_bytes(get_result["result"]))#.right(6))
	else:
		print("no")
		pass

	http_request_delete_tx_write.queue_free()
	




# Called from Rust
func set_signed_data(var signature):
	
	var signed_data = "".join(["0x", signature])
	
	print(signed_data)
	
	# TEMP OFF
	
#	var http_request = HTTPRequest.new()
#	$HTTP.add_child(http_request)
#	http_request_delete_tx_write = http_request
#	http_request.connect("request_completed", self, "send_transaction_attempted")
#
#	var tx = {"jsonrpc": "2.0", "method": "eth_sendRawTransaction", "params": [signed_data], "id": 7}
#	print(signed_data)
#	var error = http_request.request(zama_rpc, 
#	[req_header], 
#	true, 
#	HTTPClient.METHOD_POST, 
#	JSON.print(tx))


func send_transaction_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	print(get_result)

	if response_code == 200:
		pass
	else:
		pass
	
	http_request_delete_tx_write.queue_free()
