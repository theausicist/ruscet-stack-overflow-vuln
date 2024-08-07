// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{context::*};

pub struct Initialize {
    router: ContractId,
    vault: ContractId,
    usdg: AssetId,
    min_execution_fee: u64,
    min_purchase_asset_amount_usd: u64
}

pub struct UpdateMinExecutionFee {
    min_execution_fee: u64,
}

pub struct UpdateMinPurchaseAssetAmountUsd {
    min_purchase_asset_amount_usd: u64,
}

pub struct UpdateGov {
    gov: Account,
}

/*
 ___                                    
|_ _|_ __   ___ _ __ ___  __ _ ___  ___ 
 | || '_ \ / __| '__/ _ \/ _` / __|/ _ \
 | || | | | (__| | |  __/ (_| \__ \  __/
|___|_| |_|\___|_|  \___|\__,_|___/\___|
*/
pub struct CreateIncreaseOrder {
    account: Address,
    order_index: u64,
    purchase_asset: AssetId,
    purchase_asset_amount: u256,
    collateral_asset: AssetId,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
}

pub struct CancelIncreaseOrder {
    account: Address,
    order_index: u64,
    purchase_asset: AssetId,
    purchase_asset_amount: u256,
    collateral_asset: AssetId,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
}

pub struct ExecuteIncreaseOrder {
    account: Address,
    order_index: u64,
    purchase_asset: AssetId,
    purchase_asset_amount: u256,
    collateral_asset: AssetId,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
    execution_price: u256,
}

pub struct UpdateIncreaseOrder {
    account: Address,
    order_index: u64,
    collateral_asset: AssetId,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
}

/*
 ____                                    
|  _ \  ___  ___ _ __ ___  __ _ ___  ___ 
| | | |/ _ \/ __| '__/ _ \/ _` / __|/ _ \
| |_| |  __/ (__| | |  __/ (_| \__ \  __/
|____/ \___|\___|_|  \___|\__,_|___/\___|
*/
pub struct CreateDecreaseOrder {
    account: Address,
    order_index: u64,
    collateral_asset: AssetId,
    collateral_delta: u256,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
}

pub struct CancelDecreaseOrder {
    account: Address,
    order_index: u64,
    collateral_asset: AssetId,
    collateral_delta: u256,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
}

pub struct ExecuteDecreaseOrder {
    account: Address,
    order_index: u64,
    collateral_asset: AssetId,
    collateral_delta: u256,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
    execution_fee: u64,
    execution_price: u256,
}

pub struct UpdateDecreaseOrder {
    account: Address,
    order_index: u64,
    collateral_asset: AssetId,
    collateral_delta: u256,
    index_asset: AssetId,
    size_delta: u256,
    is_long: bool,
    trigger_price: u256,
    trigger_above_threshold: bool,
}

/*
 ____                     
/ ___|_      ____ _ _ __  
\___ \ \ /\ / / _` | '_ \ 
 ___) \ V  V / (_| | |_) |
|____/ \_/\_/ \__,_| .__/ 
                   |_|
*/
pub struct CreateSwapOrder {
    account: Address,
    order_index: u64,
    path: Vec<AssetId>,
    amount_in: u64,
    min_out: u64,
    trigger_ratio: u64,
    trigger_above_threshold: bool,
    should_unwrap: bool,
    execution_fee: u64,
}

pub struct CancelSwapOrder {
    account: Address,
    order_index: u64,
    path: Vec<AssetId>,
    amount_in: u64,
    min_out: u64,
    trigger_ratio: u64,
    trigger_above_threshold: bool,
    should_unwrap: bool,
    execution_fee: u64,
}

pub struct UpdateSwapOrder {
    account: Address,
    order_index: u64,
    path: Vec<AssetId>,
    amount_in: u64,
    min_out: u64,
    trigger_ratio: u64,
    trigger_above_threshold: bool,
    should_unwrap: bool,
    execution_fee: u64,
}

pub struct ExecuteSwapOrder {
    account: Address,
    order_index: u64,
    path: Vec<AssetId>,
    amount_in: u64,
    min_out: u64,
    amount_out: u64,
    trigger_ratio: u64,
    trigger_above_threshold: bool,
    should_unwrap: bool,
    execution_fee: u64,
}