// SPDX-License-Identifier: Apache-2.0
contract;
 
use std::{
    block::timestamp,
	context::*, 
	asset::*, 
	call_frames::contract_id
};
 
abi Utils {
	fn get_timestamp() -> u64;

	fn get_contr_balance(
		contr: ContractId,
		asset: AssetId
	) -> u64;
}

impl Utils for Contract {
	/// Get the internal balance of a specific coin at a specific contract.
	fn get_timestamp() -> u64 {
		timestamp()
	}

	fn get_contr_balance(
		contr: ContractId,
		asset: AssetId
	) -> u64 {
		balance_of(contr, asset)
	}
}
 