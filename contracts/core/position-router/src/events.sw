// SPDX-License-Identifier: Apache-2.0
library;

use helpers::fixed_vec::FixedVecAssetIdSize5;

/*
 ___                                    
|_ _|_ __   ___ _ __ ___  __ _ ___  ___ 
 | || '_ \ / __| '__/ _ \/ _` / __|/ _ \
 | || | | | (__| | |  __/ (_| \__ \  __/
|___|_| |_|\___|_|  \___|\__,_|___/\___|
*/
pub struct CreateIncreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    amount_in: u64,
    min_out: u64,
    size_delta: u256,
    is_long: bool,
    acceptable_price: u256,
    execution_fee: u64,
    index: u64,
    queue_index: u64,
    block_height: u32,
    block_time: u64,
}

pub struct ExecuteIncreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    amount_in: u64,
    min_out: u64,
    size_delta: u256,
    is_long: bool,
    acceptable_price: u256,
    execution_fee: u64,
    block_gap: u32,
    time_gap: u64
}

pub struct CancelIncreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    amount_in: u64,
    min_out: u64,
    size_delta: u256,
    is_long: bool,
    acceptable_price: u256,
    execution_fee: u64,
    block_gap: u32,
    time_gap: u64
}

/*
 ____                                    
|  _ \  ___  ___ _ __ ___  __ _ ___  ___ 
| | | |/ _ \/ __| '__/ _ \/ _` / __|/ _ \
| |_| |  __/ (__| | |  __/ (_| \__ \  __/
|____/ \___|\___|_|  \___|\__,_|___/\___|
*/

pub struct CreateDecreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    receiver: Address,
    acceptable_price: u256,
    min_out: u64,
    execution_fee: u64,
    index: u64,
    queue_index: u64,
    block_height: u32,
    block_time: u64
}

pub struct ExecuteDecreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    receiver: Address,
    acceptable_price: u256,
    min_out: u64,
    execution_fee: u64,
    block_gap: u32,
    time_gap: u64
}

pub struct CancelDecreasePosition {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    receiver: Address,
    acceptable_price: u256,
    min_out: u64,
    execution_fee: u64,
    block_gap: u32,
    time_gap: u64
}

/*
 __  __ _          
|  \/  (_)___  ___ 
| |\/| | / __|/ __|
| |  | | \__ \ (__ 
|_|  |_|_|___/\___|
*/
pub struct SetPositionKeeper {
    account: Address,
    is_active: bool
}

pub struct SetMinExecutionFee {
    min_execution_fee: u64
}

pub struct SetIsLeverageEnabled {
    is_leverage_enabled: bool
}

pub struct SetDelayValues {
    min_block_delay_keeper: u32,
    min_time_delay_public: u64,
    max_time_delay: u64 
}

pub struct SetRequestKeysStartValues {
    increase_position_request_keys_start: u64,
    decrease_position_request_keys_start: u64
}

pub struct SetCallbackGasLimit {
    callback_gas_limit: u64
}

pub struct SetCustomCallbackGasLimit {
    callback_target: ContractId,
    callback_gas_limit: u64
}

pub struct Callback {
    callback_target: ContractId,
    success: bool,
    callback_gas_limit: u64
}