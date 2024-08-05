// SPDX-License-Identifier: Apache-2.0
contract;

/*
 ____           _ _   _               ____             _            
|  _ \ ___  ___(_) |_(_) ___  _ __   |  _ \ ___  _   _| |_ ___ _ __ 
| |_) / _ \/ __| | __| |/ _ \| '_ \  | |_) / _ \| | | | __/ _ \ '__|
|  __/ (_) \__ \ | |_| | (_) | | | | |  _ < (_) | |_| | ||  __/ |   
|_|   \___/|___/_|\__|_|\___/|_| |_| |_| \_\___/ \__,_|\__\___|_|   
*/

mod events;
mod errors;

use std::{
    auth::msg_sender,
    block::{timestamp, height},
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    constants::BASE_ASSET_ID,
    context::*,
    revert::require,
    asset::{
        force_transfer_to_contract,
        mint_to_address,
        transfer_to_address,
    },
    storage::storage_vec::*,
    primitive_conversions::u64::*
};
use std::hash::*;
use core_interfaces::{
    base_position_manager::BasePositionManager,
    position_router::*,
    position_router_callback_receiver::PositionRouterCallbackReceiver,
};
use helpers::{
    context::*,
    utils::*,
    signed_64::*,
    transfer::transfer_assets,
    fixed_vec::FixedVecAssetIdSize5
};
use events::*;
use errors::*;

storage {
    // gov is not restricted to an `Address` (EOA) or a `Contract` (external)
    // because this can be either a regular EOA (Address) or a Multisig (Contract)
    gov: Account = ZERO_ACCOUNT,
    is_initialized: bool = false,
    is_leverage_enabled: bool = true,
    
    vault: ContractId = ZERO_CONTRACT,
    base_position_manager: ContractId = ZERO_CONTRACT,

    min_execution_fee: u64 = 0,
    min_block_delay_keeper: u32 = 0,
    min_time_delay_public: u64 = 0,
    max_time_delay: u64 = 0,

    increase_position_request_keys: StorageVec<b256> = StorageVec {},
    decrease_position_request_keys: StorageVec<b256> = StorageVec {},

    increase_position_request_keys_start: u64 = 0,
    decrease_position_request_keys_start: u64 = 0,

    callback_gas_limit: u64 = 0,
    custom_callback_gas_limits: StorageMap<ContractId, u64> 
        = StorageMap::<ContractId, u64> {},

    is_position_keeper: StorageMap<Address, bool> 
        = StorageMap::<Address, bool> {},

    increase_positions_index: StorageMap<Address, u64> 
        = StorageMap::<Address, u64> {},
    increase_position_requests: StorageMap<b256, IncreasePositionRequest> 
        = StorageMap::<b256, IncreasePositionRequest> {},

    decrease_positions_index: StorageMap<Address, u64> 
        = StorageMap::<Address, u64> {},
    decrease_position_requests: StorageMap<b256, DecreasePositionRequest> 
        = StorageMap::<b256, DecreasePositionRequest> {},
}

impl PositionRouter for Contract {
    #[storage(read, write)]
    fn initialize(
        base_position_manager: ContractId,
        vault: ContractId,
        vault_storage: ContractId,
        router: ContractId,
        shorts_tracker: ContractId,
        deposit_fee: u64,
        min_execution_fee: u64
    ) {
        require(!storage.is_initialized.read(), Error::PositionRouterAlreadyInitialized);
        storage.is_initialized.write(true);
        storage.gov.write(get_sender());

        storage.min_execution_fee.write(min_execution_fee);
        storage.vault.write(vault);
        storage.base_position_manager.write(base_position_manager);

        abi(BasePositionManager, base_position_manager.value).initialize(
            get_sender(),
            vault,
            vault_storage,
            router,
            shorts_tracker,
            deposit_fee
        );
    }

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
    ) {
        _only_gov();
        storage.is_position_keeper.insert(account, is_active);
        log(SetPositionKeeper {
            account,
            is_active
        });
    }

    #[storage(read, write)]
    fn set_callback_gas_limit(callback_gas_limit: u64) {
        _only_gov();
        storage.callback_gas_limit.write(callback_gas_limit);
        log(SetCallbackGasLimit { callback_gas_limit });
    }

    #[storage(read, write)]
    fn set_custom_callback_gas_limit(
        callback_target: ContractId,
        callback_gas_limit: u64
    ) {
        _only_gov();
        storage.custom_callback_gas_limits.insert(callback_target, callback_gas_limit);
        log(SetCustomCallbackGasLimit { callback_target, callback_gas_limit });
    }

    #[storage(read, write)]
    fn set_min_execution_fee(min_execution_fee: u64) {
        _only_gov();
        storage.min_execution_fee.write(min_execution_fee);
        log(SetMinExecutionFee { min_execution_fee });
    }

    #[storage(read, write)]
    fn set_is_leverage_enabled(is_leverage_enabled: bool) {
        _only_gov();
        storage.is_leverage_enabled.write(is_leverage_enabled);
        log(SetIsLeverageEnabled { is_leverage_enabled });
    }

    #[storage(read, write)]
    fn set_delay_values(
        min_block_delay_keeper: u32,
        min_time_delay_public: u64,
        max_time_delay: u64 
    ) {
        _only_gov();
        storage.min_block_delay_keeper.write(min_block_delay_keeper);
        storage.min_time_delay_public.write(min_time_delay_public);
        storage.max_time_delay.write(max_time_delay);

        log(SetDelayValues { 
            min_block_delay_keeper,
            min_time_delay_public,
            max_time_delay
        });
    }

    #[storage(read, write)]
    fn set_request_key_start_values(
        increase_position_request_keys_start: u64,
        decrease_position_request_keys_start: u64
    ) {
        _only_gov();
        storage.increase_position_request_keys_start
            .write(increase_position_request_keys_start);
        storage.decrease_position_request_keys_start
            .write(decrease_position_request_keys_start);

        log(SetRequestKeysStartValues { 
            increase_position_request_keys_start,
            decrease_position_request_keys_start
        });
    }

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
    ) {
        _only_position_keeper();

        let mut end_index = end_index_;
        let mut index = storage.increase_position_request_keys_start.read();
        let len = storage.increase_position_request_keys.len();

        if index >= len {
            return;
        }

        if end_index > len {
            end_index = len;
        }

        while index < end_index {
            let key = storage.increase_position_request_keys.get(index).unwrap().read();

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old or if the slippage is
            // higher than what the user specified, or if there is insufficient liquidity for the position
            // in case an error was thrown, cancel the request
            let (was_executed, is_error) = _execute_increase_position(
                key, 
                execution_fee_receiver,
                true
            );

            // if the call results in an error, cancel it
            if is_error {
                let (was_cancelled, _) = _cancel_increase_position(key, execution_fee_receiver, true);
                if !was_cancelled {
                    break;
                }
            }

            if !was_executed {
                break;
            }

            storage.increase_position_request_keys.remove(index);
            index += 1;
        }

        storage.increase_position_request_keys_start.write(index);
    }

    #[storage(read, write)]
    fn execute_increase_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool {
        let (is_executed, _) = _execute_increase_position(
            key,
            execution_fee_receiver,
            false
        );

        is_executed
    }

    #[storage(read, write)]
    fn cancel_increase_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool {
        let (is_cancelled, _) = _cancel_increase_position(
            key,
            execution_fee_receiver,
            false
        );

        is_cancelled
    }

    #[storage(read, write)]
    fn execute_decrease_positions(
        end_index_: u64,
        execution_fee_receiver: Address
    ) {
        _only_position_keeper();

        let mut end_index = end_index_;
        let mut index = storage.decrease_position_request_keys_start.read();
        let len = storage.decrease_position_request_keys.len();

        if index >= len {
            return;
        }

        if end_index > len {
            end_index = len;
        }

        while index < end_index {
            let key = storage.decrease_position_request_keys.get(index).unwrap().read();

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old
            // in case an error was thrown, cancel the request
            let (was_executed, is_error) = _execute_decrease_position(
                key, 
                execution_fee_receiver,
                true
            );

            // if the call results in an error, cancel it
            if is_error {
                let (was_cancelled, _) = _cancel_decrease_position(key, execution_fee_receiver, true);
                if !was_cancelled {
                    break;
                }
            }

            if !was_executed {
                break;
            }

            storage.decrease_position_request_keys.remove(index);
            index += 1;
        }

        storage.decrease_position_request_keys_start.write(index);
    }

    #[storage(read, write)]
    fn execute_decrease_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool {
        let (is_executed, _) = _execute_decrease_position(
            key,
            execution_fee_receiver,
            false
        );

        is_executed
    }

    #[storage(read, write)]
    fn cancel_decrease_position(
        key: b256,
        execution_fee_receiver: Address
    ) -> bool {
        let (is_cancelled, _) = _cancel_decrease_position(
            key,
            execution_fee_receiver,
            false
        );

        is_cancelled
    }

    fn get_request_key(
        account: Address,
        index: u64
    ) -> b256 {
        _get_request_key(
            account,
            index
        )
    }

    #[storage(read)]
    fn get_increase_position_request_keys(key: u64) -> b256 {
        storage.increase_position_request_keys.get(key).unwrap().read()
    }

    #[storage(read)]
    fn get_increase_position_request_path(key: b256) -> Vec<AssetId> {
        let request = storage.increase_position_requests.get(key)
            .try_read().unwrap_or(IncreasePositionRequest::default());
        
        request.path.to_vec()
    }

    #[storage(read)]
    fn get_decrease_position_request_path(key: b256) -> Vec<AssetId> {
        let request = storage.decrease_position_requests.get(key)
            .try_read().unwrap_or(DecreasePositionRequest::default());
        
        request.path.to_vec()
    }

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
    ) -> b256 {
        let account = get_address_or_revert();

        require(
            execution_fee >= storage.min_execution_fee.read(),
            Error::PositionRouterFeeTooLow
        );
        require(
            path.len() == 1 || path.len() == 2,
            Error::PositionRouterInvalidPathLen
        );

        _set_trader_referral_code(referral_code);

        let fixed_vec = FixedVecAssetIdSize5::from_vec(path);
        
        let request = IncreasePositionRequest {
            account,
            path: fixed_vec,
            index_asset,
            amount_in,
            min_out,
            size_delta,
            is_long,
            acceptable_price,
            execution_fee,
            has_collateral_in_eth: path.get(0).unwrap() == BASE_ASSET_ID,
            callback_target,
            block_height: height(),
            block_time: timestamp()
        };

        let index = storage.increase_positions_index.get(account).try_read().unwrap_or(0) + 1;
        storage.increase_positions_index.insert(account, index);

        let key = _get_request_key(account, index);

        storage.increase_position_requests.insert(key, request);
        storage.increase_position_request_keys.push(key);

        log(CreateIncreasePosition {
            account,
            path: fixed_vec,
            index_asset,
            amount_in,
            min_out,
            size_delta,
            is_long,
            acceptable_price,
            execution_fee,
            index,
            queue_index: storage.increase_position_request_keys.len() - 1,
            block_height: height(),
            block_time: timestamp()
        });

        key
    }

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
    ) -> b256 {
        let account = get_address_or_revert();

        require(
            execution_fee >= storage.min_execution_fee.read(),
            Error::PositionRouterFeeTooLow
        );
        require(
            path.len() == 1 || path.len() == 2,
            Error::PositionRouterInvalidPathLen
        );

        let fixed_vec = FixedVecAssetIdSize5::from_vec(path);
        
        let request = DecreasePositionRequest {
            account,
            path: fixed_vec,
            index_asset,
            collateral_delta,
            size_delta,
            is_long,
            acceptable_price,
            min_out,
            execution_fee,
            receiver,
            withdraw_eth,
            callback_target,
            block_height: height(),
            block_time: timestamp()
        };

        let index = storage.decrease_positions_index.get(account).try_read().unwrap_or(0) + 1;
        storage.decrease_positions_index.insert(account, index);

        let key = _get_request_key(account, index);

        storage.decrease_position_requests.insert(key, request);
        storage.decrease_position_request_keys.push(key);

        log(CreateDecreasePosition {
            account,
            path: fixed_vec,
            index_asset,
            collateral_delta,
            size_delta,
            is_long,
            acceptable_price,
            min_out,
            execution_fee,
            receiver,
            index,
            queue_index: storage.decrease_position_request_keys.len() - 1,
            block_height: height(),
            block_time: timestamp()
        });

        key
    }

    #[storage(read)]
    fn get_request_queue_lengths() -> (u64, u64, u64, u64) {
        (
            storage.increase_position_request_keys_start.read(),
            storage.increase_position_request_keys.len(),
            storage.decrease_position_request_keys_start.read(),
            storage.decrease_position_request_keys.len(),
        )
    }
}

/*
    ____  ___       _                        _ 
   / / / |_ _|_ __ | |_ ___ _ __ _ __   __ _| |
  / / /   | || '_ \| __/ _ \ '__| '_ \ / _` | |
 / / /    | || | | | ||  __/ |  | | | | (_| | |
/_/_/    |___|_| |_|\__\___|_|  |_| |_|\__,_|_|
*/

#[storage(read)]
fn _only_gov() {
    require(get_sender() == storage.gov.read(), Error::PositionRouterForbidden);
}

#[storage(read)]
fn _only_position_keeper() {
    require(
        storage.is_position_keeper.get(get_address_or_revert()).try_read().is_some(),
        Error::PositionRouterExpectedPositionKeeper
    );
}

#[storage(read)]
fn _validate_execution_or_cancellation(
    position_block_height: u32,
    position_block_time: u64,
    account: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    let sender = get_sender();
    let is_keeper_call = 
        (sender.is_contract && ContractId::from(sender.value) == contract_id()) || 
        storage.is_position_keeper.get(Address::from(sender.value)).try_read().is_some();
    
    if !storage.is_leverage_enabled.read() && !is_keeper_call {
        if disable_eager_revert {
            return (false, true);
        }
        require(false, Error::PositionRouterExpectedCallerToBeKeeper);
    }

    if is_keeper_call {
        return (
            position_block_height + storage.min_block_delay_keeper.read() <= height(),
            false
        );
    }

    if !sender.is_contract && Address::from(sender.value) != account {
        if disable_eager_revert {
            return (false, true);
        }
        require(false, Error::PositionRouterExpectedCallerToBeAccount);
    }

    if position_block_time + storage.min_time_delay_public.read() <= timestamp() {
        if disable_eager_revert {
            return (false, true);
        }

        require(false, Error::PositionRouterDelay);
    }

    (true, false)
}

#[storage(read)]
fn _validate_execution(
    position_block_height: u32,
    position_block_time: u64,
    account: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    if position_block_time + storage.min_time_delay_public.read() > timestamp() {
        if disable_eager_revert {
            return (false, true);
        }
        require(false, Error::PositionRouterExpired);
    }

    _validate_execution_or_cancellation(
        position_block_height,
        position_block_time,
        account,
        disable_eager_revert
    )
}

#[storage(read)]
fn _validate_cancellation(
    position_block_height: u32,
    position_block_time: u64,
    account: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    _validate_execution_or_cancellation(
        position_block_height,
        position_block_time,
        account,
        disable_eager_revert
    )
}

#[storage(read, write)]
fn _execute_increase_position(
    key: b256,
    execution_fee_receiver: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    let request = storage.increase_position_requests.get(key)
        .try_read().unwrap_or(IncreasePositionRequest::default());
    
    // if the request was already executed or cancelled, return true so that the 
    // executeIncreasePositions loop will continue executing the next request
    if request.account == ZERO_ADDRESS {
        return (true, false);
    }

    let (should_execute, is_execution_error) = _validate_execution(
        request.block_height,
        request.block_time,
        request.account,
        disable_eager_revert
    );
    if is_execution_error {
        return (false, true);
    }

    if !should_execute {
        return (false, false);
    }

    storage.increase_position_requests.remove(key);

    let base_position_manager = abi(
        BasePositionManager,
        storage.base_position_manager.read().value
    );
    
    if request.amount_in > 0 {
        let mut amount_in = request.amount_in;

        if request.path.len() > 1 {
            transfer_assets(
                request.path.get(0),
                Account::from(storage.vault.read()),
                request.amount_in
            );
            amount_in = base_position_manager.swap(
                request.path.to_vec(),
                request.min_out,
                Account::from(contract_id())
            );
        }

        // fee asset is the last asset in the path
        // thesis: we send the "ENTIRE" amount of `amount_in` to BasePositionManager
        // BPM will process and return any excess amount back to us
        let fee_asset = request.path.get(request.path.len() - 1);

        let after_fee_amount = base_position_manager.collect_fees{
            asset_id: fee_asset.value,
            coins: amount_in
        }(
            request.account,
            request.path.to_vec(),
            amount_in,
            request.index_asset,
            request.is_long,
            request.size_delta
        );

        transfer_assets(
            fee_asset,
            Account::from(storage.vault.read()),
            after_fee_amount
        );
    }

    base_position_manager.increase_position(
        request.account,
        request.path.get(request.path.len() - 1),
        request.index_asset,
        request.size_delta,
        request.is_long,
        request.acceptable_price
    );

    // transfer out executionfee to execution_fee_receiver
    transfer_assets(
        BASE_ASSET_ID,
        Account::from(execution_fee_receiver),
        request.execution_fee
    );

    log(ExecuteIncreasePosition {
        account: request.account,
        path: request.path,
        index_asset: request.index_asset,
        amount_in: request.amount_in,
        min_out: request.min_out,
        size_delta: request.size_delta,
        is_long: request.is_long,
        acceptable_price: request.acceptable_price,
        execution_fee: request.execution_fee,
        block_gap: height() - request.block_height, // @TODO: this might revert
        time_gap: timestamp() - request.block_time
    });

    _call_request_callback(
        request.callback_target,
        key,
        true,
        true
    );

    (true, false)
}

#[storage(read, write)]
fn _cancel_increase_position(
    key: b256,
    execution_fee_receiver: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    let request = storage.increase_position_requests.get(key).try_read().unwrap_or(IncreasePositionRequest::default());
    // if the request was already executed or cancelled, return true so that the 
    // executeIncreasePositions loop will continue executing the next request
    if request.account == ZERO_ADDRESS {
        return (true, false);
    }

    let (should_cancel, is_cancellation_error) = _validate_cancellation(
        request.block_height,
        request.block_time,
        request.account,
        true
    );
    if is_cancellation_error {
        return (false, true);
    }

    if !should_cancel {
        return (false, false);
    }

    storage.increase_position_requests.remove(key);

    // @TODO: remove `has_collateral_in_eth` requirement
    if request.has_collateral_in_eth {
        transfer_assets(
            BASE_ASSET_ID,
            Account::from(request.account),
            request.amount_in
        );
    } else {
        transfer_assets(
            request.path.get(0),
            Account::from(request.account),
            request.amount_in
        );
    }

    // transfer out executionfee to execution_fee_receiver
    transfer_assets(
        BASE_ASSET_ID,
        Account::from(execution_fee_receiver),
        request.execution_fee
    );

    log(CancelIncreasePosition {
        account: request.account,
        path: request.path,
        index_asset: request.index_asset,
        amount_in: request.amount_in,
        min_out: request.min_out,
        size_delta: request.size_delta,
        is_long: request.is_long,
        acceptable_price: request.acceptable_price,
        execution_fee: request.execution_fee,
        block_gap: height() - request.block_height, // @TODO: this might revert
        time_gap: timestamp() - request.block_time
    });

    (true, false)
}

#[storage(read, write)]
fn _execute_decrease_position(
    key: b256,
    execution_fee_receiver: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    let request = storage.decrease_position_requests.get(key)
        .try_read().unwrap_or(DecreasePositionRequest::default());
    
    // if the request was already executed or cancelled, return true so that the 
    // executeDecreasePositions loop will continue executing the next request
    if request.account == ZERO_ADDRESS {
        return (true, false);
    }

    let (should_execute, is_execution_error) = _validate_execution(
        request.block_height,
        request.block_time,
        request.account,
        disable_eager_revert
    );
    if is_execution_error {
        return (false, true);
    }

    if !should_execute {
        return (false, false);
    }

    storage.decrease_position_requests.remove(key);

    let base_position_manager = abi(
        BasePositionManager,
        storage.base_position_manager.read().value
    );

    // @TODO: forward assets to this external call
    let mut amount_out: u256 = base_position_manager.decrease_position(
        request.account,
        request.path.get(0),
        request.index_asset,
        request.collateral_delta,
        request.size_delta,
        request.is_long,
        Account::from(contract_id()),
        request.acceptable_price
    );
    
    if amount_out > 0 {
        if request.path.len() > 1 {
            transfer_assets(
                request.path.get(0),
                Account::from(storage.vault.read()),
                // @TODO: potential revert here
                u64::try_from(amount_out).unwrap()
            );

            amount_out = base_position_manager.swap(
                request.path.to_vec(),
                request.min_out,
                Account::from(contract_id())
            ).as_u256();
        }

        transfer_assets(
            request.path.get(request.path.len() - 1),
            Account::from(storage.vault.read()),
            // @TODO: potential revert here
            u64::try_from(amount_out).unwrap()
        );
    }

    transfer_assets(
        BASE_ASSET_ID,
        Account::from(execution_fee_receiver),
        request.execution_fee
    );

    log(ExecuteDecreasePosition {
        account: request.account,
        path: request.path,
        index_asset: request.index_asset,
        collateral_delta: request.collateral_delta,
        min_out: request.min_out,
        size_delta: request.size_delta,
        is_long: request.is_long,
        receiver: request.receiver,
        acceptable_price: request.acceptable_price,
        execution_fee: request.execution_fee,
        block_gap: height() - request.block_height, // @TODO: this might revert
        time_gap: timestamp() - request.block_time
    });

    _call_request_callback(
        request.callback_target,
        key,
        true,
        false
    );

    (true, false)
}

#[storage(read, write)]
fn _cancel_decrease_position(
    key: b256,
    execution_fee_receiver: Address,
    disable_eager_revert: bool
) -> (bool, bool) {
    let request = storage.decrease_position_requests.get(key).try_read().unwrap_or(DecreasePositionRequest::default());
    // if the request was already executed or cancelled, return true so that the 
    // executeDecreasePositions loop will continue executing the next request
    if request.account == ZERO_ADDRESS {
        return (true, false);
    }

    let (should_cancel, is_cancellation_error) = _validate_cancellation(
        request.block_height,
        request.block_time,
        request.account,
        true
    );
    if is_cancellation_error {
        return (false, true);
    }

    if !should_cancel {
        return (false, false);
    }

    storage.decrease_position_requests.remove(key);

    transfer_assets(
        BASE_ASSET_ID,
        Account::from(execution_fee_receiver),
        request.execution_fee
    );

    log(CancelDecreasePosition {
        account: request.account,
        path: request.path,
        index_asset: request.index_asset,
        collateral_delta: request.collateral_delta,
        receiver: request.receiver,
        min_out: request.min_out,
        size_delta: request.size_delta,
        is_long: request.is_long,
        acceptable_price: request.acceptable_price,
        execution_fee: request.execution_fee,
        block_gap: height() - request.block_height, // @TODO: this might revert
        time_gap: timestamp() - request.block_time
    });

    (true, false)
}

fn _call_request_callback(
    callback_target: ContractId,
    key: b256,
    was_executed: bool,
    is_increase: bool 
) {
    if callback_target == ZERO_CONTRACT {
        return;
    }

    // @TODO: handle gas forwarding for callback
    abi(PositionRouterCallbackReceiver, callback_target.value)
        .ruscet_position_callback(
            key,
            was_executed,
            is_increase
        );

    log(Callback {
        callback_target,
        success: true,
        callback_gas_limit: 0 // @TODO: update when gas forwarding supported
    });
}

fn _get_request_key(
    account: Address,
    index: u64
) -> b256 {
    keccak256(RequestKey {
        account,
        index
    })
}

// #[storage(read)]
fn _set_trader_referral_code(referral_code: b256) {
    // let _referral_storage = abi(
    //     BasePositionManager, 
    //     storage.base_position_manager.read().value
    // )._referral_storage();

    // if referral_code == ZERO || _referral_storage == ZERO {
    //     return;
    // }

    // let referral_storage = abi(ReferralStorage, _referral_storage);

    // // skip setting of the referral code if the user already has a referral code
    // if referral_storage.trader_referral_codes(get_address_or_revert()) != ZERO {
    //     return;
    // }

    // referral_storage.set_trader_referral_codes(get_address_or_revert(), referral_code);
}