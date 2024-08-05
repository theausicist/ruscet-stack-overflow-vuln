// SPDX-License-Identifier: Apache-2.0
contract;
 
use std::{constants::ZERO_B256, context::*, asset::*, call_frames::contract_id, hash::*};
use std::{
    asset::*
};
use helpers::{
	context::*,
	utils::*,
    transfer::transfer_assets,
	utils::*
};

abi Transfer {
	#[storage(read, write)]
	fn initialize();
	#[storage(read, write)]
	fn transfer_out(to: Address);

	fn get_asset_id() -> AssetId;
	fn get_balance_for(asset_id: AssetId) -> u64;
}

storage {
	balance: u64 = 0
}

impl Transfer for Contract {
	#[storage(read, write)]
	fn initialize() {
		storage.balance.write(1_000_000);
		mint(ZERO_B256, 1_000_000);
	}

	#[storage(read, write)]
	fn transfer_out(to: Address) {
		transfer_assets(
	        AssetId::new(contract_id(), ZERO_B256),
			Account::from(to),
			69_420
		);
		transfer(
			Identity::Address(to),
			AssetId::new(contract_id(), ZERO_B256),
			69_420
		);
		transfer_to_address(
			to,
			AssetId::new(contract_id(), ZERO_B256),
			69_420
		);

		storage.balance.write(
			storage.balance.read() - 69_420
		);
	}

	fn get_asset_id() -> AssetId {
        AssetId::new(contract_id(), ZERO_B256)
	}

	/// Get the internal balance of a specific coin at a specific contract.
	fn get_balance_for(asset_id: AssetId) -> u64 {
		balance_of(contract_id(), asset_id)
	}
}
 