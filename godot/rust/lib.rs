use gdnative::{prelude::*, core_types::ToVariant};
use ethers::{core::{abi::{struct_def::StructFieldType, AbiEncode, AbiDecode}, types::*, k256::elliptic_curve::consts::U8}, signers::*, providers::*, prelude::SignerMiddleware};
use ethers_contract::{abigen};
use ethers::core::types::transaction::eip2718::TypedTransaction;
use std::{convert::TryFrom, sync::Arc};
use tokio::runtime::{Builder, Runtime};
use tokio::task::LocalSet;
use tokio::macros::support::{Pin, Poll};
use futures::Future;
use tfhe::{prelude::*, CompactFheUint8List};
use tfhe::{generate_keys, set_server_key, ConfigBuilder, FheUint32, FheUint8, CompactFheUint32List, CompactPublicKey};
use hex::*;
use bincode::deserialize;



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
#[tokio::main]
async fn encrypt_message (key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, key_material: GodotString, message: u8, ui_node: Ref<Control>) -> NewFuture {
    
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

    let ser_message = bincode::serialize(&message).unwrap();

    let message_bytes = &ser_message[..];

    let fhe_value = CompactFheUint8List::try_encrypt(message_bytes, &chain_public_key).unwrap();

    let ser_val = bincode::serialize(&fhe_value).unwrap();

    let fhe_ethers_bytes: Bytes = ser_val.into();

    let calldata = contract.set_number(fhe_ethers_bytes).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(1000000)
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
fn check_queue(key: PoolArray<u8>, chain_id: u64, fhe_contract_address: GodotString, rpc: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 

let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
    
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);

let user_address = wallet.address();

let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");

let contract_address: Address = fhe_contract_address.to_string().parse().unwrap();

let client = SignerMiddleware::new(provider, wallet);

let contract = FHEABI::new(contract_address.clone(), Arc::new(client.clone()));

let calldata = contract.success().calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

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

