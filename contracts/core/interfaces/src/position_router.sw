// SPDX-License-Identifier: Apache-2.0
library;

use std::hash::*;
use helpers::{
    context::*,
    signed_64::*,
    fixed_vec::FixedVecAssetIdSize5,
    utils::*
};

pub struct IncreasePositionRequest {
    account: Address,
    path: FixedVecAssetIdSize5,
    index_asset: AssetId,
    amount_in: u64,
    min_out: u64,
    size_delta: u256,
    is_long: bool,
    acceptable_price: u256,
    execution_fee: u64,
    block_height: u32,
    block_time: u64,
    has_collateral_in_eth: bool,
    callback_target: ContractId
}

pub struct DecreasePositionRequest {
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
    block_height: u32,
    block_time: u64,
    withdraw_eth: bool,
    callback_target: ContractId
}

pub struct RequestKey {
    account: Address,
    index: u64
}

abi PositionRouter {
    #[storage(read, write)]
    fn initialize(
        base_position_manager: ContractId,
        vault: ContractId,
        vault_storage: ContractId,
        router: ContractId,
        shorts_tracker: ContractId,
        deposit_fee: u64,
        min_execution_fee: u64
    );

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn set_position_keeper(
        account: Address,
        is_active: bool 
    );

    #[storage(read, write)]
    fn set_callback_gas_limit(callback_gas_limit: u64);

    #[storage(read, write)]
    fn set_custom_callback_gas_limit(
        callback_target: ContractId,
        callback_gas_limit: u64
    );

    #[storage(read, write)]
    fn set_min_execution_fee(min_execution_fee: u64);

    #[storage(read, write)]
    fn set_is_leverage_enabled(is_leverage_enabled: bool);

    #[storage(read, write)]
    fn set_delay_values(
        min_block_delay_keeper: u32,
        min_time_delay_public: u64,
        max_time_delay: u64 
    );

    #[storage(read, write)]
    fn set_request_key_start_values(
        increase_position_request_keys_start: u64,
        decrease_position_request_keys_start: u64
    );

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[storage(read, write)]
    fn execute_increase_positions(
        end_index_: u64,
        execution_fee_receiver: Address
    );

    #[storage(read, write)]
    fn execute_increase_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool;

    #[storage(read, write)]
    fn cancel_increase_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool;

    #[storage(read, write)]
    fn execute_decrease_positions(
        end_index_: u64,
        execution_fee_receiver: Address
    );

    #[storage(read, write)]
    fn execute_decrease_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool;

    #[storage(read, write)]
    fn cancel_decrease_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool;

    fn get_request_key(
        account: Address,
        index: u64
    ) -> b256;

    #[storage(read)]
    fn get_increase_position_request_keys(key: u64) -> b256;

    #[storage(read)]
    fn get_increase_position_request_path(key: b256) -> Vec<AssetId>;

    #[storage(read)]
    fn get_decrease_position_request_path(key: b256) -> Vec<AssetId>;

    #[storage(read, write)]
    fn create_increase_position(
        path: Vec<AssetId>,
        index_asset: AssetId,
        amount_in: u64,
        min_out: u64,
        size_delta: u256,
        is_long: bool,
        acceptable_price: u256,
        execution_fee: u64,
        referral_code: b256,
        callback_target: ContractId
    ) -> b256;

    #[storage(read, write)]
    fn create_decrease_position(
        path: Vec<AssetId>,
        index_asset: AssetId,
        collateral_delta: u256,
        size_delta: u256,
        is_long: bool,
        receiver: Address,
        acceptable_price: u256,
        min_out: u64,
        execution_fee: u64,
        withdraw_eth: bool,
        callback_target: ContractId
    ) -> b256;

    #[storage(read)]
    fn get_request_queue_lengths() -> (u64, u64, u64, u64);
}

impl IncreasePositionRequest {
    pub fn default() -> Self {
        Self {
            account: ZERO_ADDRESS,
            path: FixedVecAssetIdSize5::default(),
            index_asset: ZERO_ASSET,
            amount_in: 0,
            min_out: 0,
            size_delta: 0,
            is_long: false,
            acceptable_price: 0,
            execution_fee: 0,
            block_height: 0,
            block_time: 0,
            has_collateral_in_eth: false,
            callback_target: ZERO_CONTRACT
        }
    }
}

impl DecreasePositionRequest {
    pub fn default() -> Self {
        Self {
            account: ZERO_ADDRESS,
            path: FixedVecAssetIdSize5::default(),
            index_asset: ZERO_ASSET,
            collateral_delta: 0,
            size_delta: 0,
            is_long: false,
            receiver: ZERO_ADDRESS,
            acceptable_price: 0,
            min_out: 0,
            execution_fee: 0,
            block_height: 0,
            block_time: 0,
            withdraw_eth: false,
            callback_target: ZERO_CONTRACT
        }
    }
}

impl Hash for RequestKey {
    fn hash(self, ref mut state: Hasher) {
        self.account.hash(state);
        self.index.hash(state);
    }
}