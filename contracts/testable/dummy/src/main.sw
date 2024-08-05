// SPDX-License-Identifier: Apache-2.0
contract;
 
use std::{constants::ZERO_B256, context::*, asset::*, call_frames::contract_id};
 
abi Dummy {
	fn get_balance_for(asset_id: AssetId) -> u64;
}

impl Dummy for Contract {
	/// Get the internal balance of a specific coin at a specific contract.
	fn get_balance_for(asset_id: AssetId) -> u64 {
		balance_of(contract_id(), asset_id)
	}
}
 