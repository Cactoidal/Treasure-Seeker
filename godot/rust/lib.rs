use gdnative::{prelude::*, core_types::ToVariant};
use ethers::{core::{abi::{struct_def::StructFieldType, AbiEncode, AbiDecode}, types::*, k256::elliptic_curve::consts::U8}, signers::*, providers::*, prelude::SignerMiddleware};
use ethers_contract::{abigen, Eip712, EthAbiType};
use ethers::core::types::transaction::eip2718::TypedTransaction;
use ethers::types::transaction::eip712::Eip712;
use ethers::utils::keccak256;
use std::{convert::TryFrom, sync::Arc};
use tokio::runtime::{Builder, Runtime};
use tokio::task::LocalSet;
use tokio::macros::support::{Pin, Poll};
use futures::Future;
use tfhe::{prelude::*, CompactFheUint8List};
use tfhe::{generate_keys, set_server_key, ConfigBuilder, FheUint32, FheUint8, CompactFheUint32List, CompactPublicKey};
use hex::*;
use serde_json::json;
use bincode::deserialize;
use libsodium_sys::{crypto_box_keypair, crypto_box_seal_open, crypto_box_SEALBYTES};



thread_local! {
    static EXECUTOR: &'static SharedLocalPool = {
        Box::leak(Box::new(SharedLocalPool::default()))
    };
}

#[derive(Default)]
struct SharedLocalPool {
    local_set: LocalSet,
}

impl futures::task::LocalSpawn for SharedLocalPool {
    fn spawn_local_obj(
        &self,
        future: futures::task::LocalFutureObj<'static, ()>,
    ) -> Result<(), futures::task::SpawnError> {
        self.local_set.spawn_local(future);

        Ok(())
    }
}


fn init(handle: InitHandle) {
    gdnative::tasks::register_runtime(&handle);
    gdnative::tasks::set_executor(EXECUTOR.with(|e| *e));

    handle.add_class::<Fhe>();
}

abigen!(
    FHEABI,
    "./FHEABI.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

struct NewFuture(Result<(), Box<dyn std::error::Error + 'static>>);

impl ToVariant for NewFuture {
    fn to_variant(&self) -> Variant {todo!()}
}

struct NewStructFieldType(StructFieldType);

impl OwnedToVariant for NewStructFieldType {
    fn owned_to_variant(self) -> Variant {
        todo!()
    }
}

impl Future for NewFuture {
    type Output = NewStructFieldType;
    fn poll(self: Pin<&mut Self>, _: &mut std::task::Context<'_>) -> Poll<<Self as futures::Future>::Output> { todo!() }
}

#[derive(Eip712, Clone, EthAbiType, Debug)]
#[eip712(
name = "Authorization token",
version = "1",
chain_id = 8009,
verifying_contract = "0x4F8aE29A3afB656dB0D947dD78969Aec7E148161"
)]
struct Reencrypt {
    publicKey: [u8; 32]
}

#[derive(NativeClass, Debug, ToVariant, FromVariant)]
#[inherit(Node)]
struct Fhe;

#[methods]
impl Fhe {
    fn new(_owner: &Node) -> Self {
        Fhe
    }

#[method]
fn get_address(key: PoolArray<u8>) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
 
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();

let wallet: LocalWallet = prewallet.with_chain_id(Chain::Sepolia);

let address = wallet.address();

let address_string = address.encode_hex();

let key_slice = match address_string.char_indices().nth(*&0 as usize) {
    Some((_pos, _)) => (&address_string[26..]).to_string(),
    None => "".to_string(),
    };

let return_string: GodotString = format!("0x{}", key_slice).into();

return_string

}

#[method]
fn get_opponent(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 

let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);

let user_address: Address = wallet.address();

let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");

let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();

let client = SignerMiddleware::new(provider, wallet);

let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

let calldata = contract.current_opponent(user_address).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


#[method]
#[tokio::main]
async fn join_match(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let calldata = contract.join_match().calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}

#[method]
#[tokio::main]
async fn initialize_player(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let calldata = contract.initialize_point_balance().calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}


#[method]
#[tokio::main]
async fn set_number(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, key_material: GodotString, _trap1: u8, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let raw_hex: String = key_material.to_string();
    
    let decoded: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();

    let d_vec: Vec<u8> = decoded.iter().map(|x| x.clone()).collect();
    
    let d_bytes = &d_vec[..]; 

    let chain_public_key: CompactPublicKey = bincode::deserialize(d_bytes).unwrap();

    let ser_trap1 = bincode::serialize(&_trap1).unwrap();
    let trap1_bytes = &ser_trap1[..];
    let fhe_trap1 = CompactFheUint8List::try_encrypt(trap1_bytes, &chain_public_key).unwrap();
    let ser_fhe_trap1 = bincode::serialize(&fhe_trap1).unwrap();
    let fhe_trap1_bytes: Bytes = ser_fhe_trap1.into();

    //let calldata = contract.set_number(fhe_ethers_bytes).calldata().unwrap();
    let calldata = contract.set_number(fhe_trap1_bytes).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}



#[method]
#[tokio::main]
async fn set_traps(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, key_material: GodotString, _trap1: u8, _trap2: u8, _trap3: u8, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let raw_hex: String = key_material.to_string();
    
    let decoded: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();

    let d_vec: Vec<u8> = decoded.iter().map(|x| x.clone()).collect();
    
    let d_bytes = &d_vec[..]; 

    let chain_public_key: CompactPublicKey = bincode::deserialize(d_bytes).unwrap();

    let ser_trap1 = bincode::serialize(&_trap1).unwrap();
    let trap1_bytes = &ser_trap1[..];
    let fhe_trap1 = CompactFheUint8List::try_encrypt(trap1_bytes, &chain_public_key).unwrap();
    let ser_fhe_trap1 = bincode::serialize(&fhe_trap1).unwrap();
    let fhe_trap1_bytes: Bytes = ser_fhe_trap1.into();

    let ser_trap2 = bincode::serialize(&_trap2).unwrap();
    let trap2_bytes = &ser_trap2[..];
    let fhe_trap2 = CompactFheUint8List::try_encrypt(trap2_bytes, &chain_public_key).unwrap();
    let ser_fhe_trap2 = bincode::serialize(&fhe_trap2).unwrap();
    let fhe_trap2_bytes: Bytes = ser_fhe_trap2.into();

    let ser_trap3 = bincode::serialize(&_trap3).unwrap();
    let trap3_bytes = &ser_trap3[..];
    let fhe_trap3 = CompactFheUint8List::try_encrypt(trap3_bytes, &chain_public_key).unwrap();
    let ser_fhe_trap3 = bincode::serialize(&fhe_trap3).unwrap();
    let fhe_trap3_bytes: Bytes = ser_fhe_trap3.into();

    //let calldata = contract.set_number(fhe_ethers_bytes).calldata().unwrap();
    let calldata = contract.set_traps(fhe_trap1_bytes, fhe_trap2_bytes, fhe_trap3_bytes).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}

#[method]
#[tokio::main]
async fn try_mine(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, location: u8, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let calldata = contract.try_mine(location.into()).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}

#[method]
#[tokio::main]
async fn stop_mining(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, ui_node: Ref<Control>) -> NewFuture {
    
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let calldata = contract.stop_mining().calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(9000000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction(&typed_tx).await.unwrap();
    let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
    };

    NewFuture(Ok(()))
}


#[method]
fn current_game_score(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 

let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);

let user_address = wallet.address();

let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");

let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();

let client = SignerMiddleware::new(provider, wallet);

let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

let calldata = contract.current_game_score(user_address).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


#[method]
fn get_points_balance(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 

let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);

let user_address = wallet.address();

let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");

let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();

let client = SignerMiddleware::new(provider, wallet);

let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

let calldata = contract.get_points_balance(user_address).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}

#[method]
#[tokio::main]
async fn get_cryptobox_keypair(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, ui_node: Ref<Control>) -> NewFuture {
    let vec = &key.to_vec();

    let keyset = &vec[..]; 
         
    let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
    let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
    
    let user_address = wallet.address();
    
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
    
    let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();
    
    let client = SignerMiddleware::new(provider, wallet.clone());
    
    let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

    let mut public_key = [0u8; libsodium_sys::crypto_box_PUBLICKEYBYTES as usize];
    let mut secret_key = [0u8; libsodium_sys::crypto_box_SECRETKEYBYTES as usize];
  
    unsafe {
    let keypair = crypto_box_keypair(public_key.as_mut_ptr(),  secret_key.as_mut_ptr());
    }

    let new_eip712 = Reencrypt {
        publicKey: public_key
    };
   
    let signature: Bytes = wallet.sign_typed_data(&new_eip712).await.unwrap().to_vec().into();

    let calldata = contract.test_decrypt(public_key, signature).calldata().unwrap();

    let hex_public_key = hex::encode(&public_key);
    let hex_secret_key = hex::encode(&secret_key);

    let node: TRef<Control> = unsafe { ui_node.assume_safe() };

    unsafe {
        node.call("set_box_keys", &[hex_public_key.to_variant(), hex_secret_key.to_variant(), calldata.to_string().to_variant()])
    };

    NewFuture(Ok(()))
}


#[method]
fn decode_crypto_box(box_public_key: GodotString, box_secret_key: GodotString, secret: GodotString) -> u8 {
    let raw_hex: String = secret.to_string();
    let decoded: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let ciphertext_vec: Vec<u8> = decoded.iter().map(|x| x.clone()).collect();
    let ciphertext_bytes = &ciphertext_vec[..]; 

    let public_vec = hex::decode(box_public_key.to_string()).unwrap();
    let public_bytes = &public_vec[..];
    
    let secret_vec = hex::decode(box_secret_key.to_string()).unwrap();
    let secret_bytes = &secret_vec[..];

    let mut public_key = [0u8; 32];
    let mut secret_key = [0u8; 32];

    public_key[..public_bytes.len()].copy_from_slice(public_bytes);
    secret_key[..secret_bytes.len()].copy_from_slice(secret_bytes);

    let mut decrypted_message = vec![0u8; ciphertext_bytes.len()];

    unsafe {
    crypto_box_seal_open(
                decrypted_message.as_mut_ptr(),
                ciphertext_bytes.as_ptr(),
                ciphertext_bytes.len() as u64, 
                public_key.as_ptr(), 
                secret_key.as_ptr());
    }

    let number = [decrypted_message[0]];
    let decrypted_number = u8::from_be_bytes(number);

    decrypted_number
}


#[method]
fn decode_hex_string (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: String = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = decoded.into();
    return_string
}

#[method]
fn decode_bool (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: bool = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_address (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Address = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_bytes (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_u256 (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: U256 = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}



#[method]
fn decode_u256_array (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Vec<U256> = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}


#[method]
fn decode_u256_array_from_bytes (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    //let bytes: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let decoded_bytes: [U256; 5] = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    godot_print!("{:?}", decoded_bytes);
    let return_string: GodotString = format!("{:?}", decoded_bytes).into();
    return_string
}



}



godot_init!(init);

