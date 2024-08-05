// SPDX-License-Identifier: Apache-2.0
contract;
 
use std::{constants::ZERO_B256, context::*, asset::*, call_frames::contract_id, hash::*};

abi NativeAssetToken {
	fn get_default_asset_id() -> AssetId;
	fn mint_coins(mint_amount: u64);
	fn burn_coins(burn_amount: u64);
	fn force_transfer_coins(coins: u64, asset_id: AssetId, target: ContractId);
	fn transfer_coins_to_output(coins: u64, asset_id: AssetId, recipient: Address);
	fn deposit();
	fn get_balance(target: ContractId, asset_id: AssetId) -> u64;
	fn this_balance() -> u64;
	fn mint_and_send_to_contract(amount: u64, destination: ContractId);
	fn mint_and_send_to_address(amount: u64, recipient: Address);
}

const SUB_ID = ZERO_B256;
 
impl NativeAssetToken for Contract {
	fn get_default_asset_id() -> AssetId {
		AssetId::from(sha256((contract_id(), ZERO_B256)))
	}

	/// Mint an amount of this contracts native asset to the contracts balance.
	fn mint_coins(mint_amount: u64) {
		// mint(sub_id, amount);
		mint(SUB_ID, mint_amount);
	}
 
	/// Burn an amount of this contracts native asset.
	fn burn_coins(burn_amount: u64) {
		// burn(sub_id, amount);
		burn(SUB_ID, burn_amount);
	}
 
	/// Transfer coins to a target contract.
	fn force_transfer_coins(coins: u64, asset_id: AssetId, target: ContractId) {
		force_transfer_to_contract(target, asset_id, coins);
	}
 
	/// Transfer coins to a transaction output to be spent later.
	fn transfer_coins_to_output(coins: u64, asset_id: AssetId, recipient: Address) {
		transfer_to_address(recipient, asset_id, coins);
	}
 
	/// Get the internal balance of a specific coin at a specific contract.
	fn get_balance(target: ContractId, asset_id: AssetId) -> u64 {
		balance_of(target, asset_id)
	}

	fn this_balance() -> u64 {
		balance_of(contract_id(), AssetId::from(sha256((contract_id(), ZERO_B256))))
	}
 
	/// Deposit tokens back into the contract.
	fn deposit() {
		assert(msg_amount() > 0);
	}
 
	/// Mint and send this contracts native token to a destination contract.
	fn mint_and_send_to_contract(amount: u64, destination: ContractId) {
		mint_to_contract(destination, SUB_ID, amount);
	}
 
	/// Mind and send this contracts native token to a destination address.
	fn mint_and_send_to_address(amount: u64, recipient: Address) {
		mint_to_address(recipient, SUB_ID, amount);
	}
}
 