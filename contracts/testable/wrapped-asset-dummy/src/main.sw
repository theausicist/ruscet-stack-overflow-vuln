// SPDX-License-Identifier: Apache-2.0
contract;
 
use std::{constants::ZERO_B256, context::*, asset::*, call_frames::*};

use interfaces::wrapped_asset::WrappedAsset;

abi WrappedAssetDummy {
	#[payable]
	fn wrap(wrapped_asset: ContractId, asset_id: AssetId, amount: u64) -> DepositDetails;
}

struct DepositDetails {
	contract_id: b256,
	asset_value: b256,
	balance_before: u64,
	balance_after: u64,
}

impl WrappedAssetDummy for Contract {
	#[payable]
	fn wrap(wrapped_asset: ContractId, asset_id: AssetId, amount: u64) -> DepositDetails {
		let balance_before = balance_of(contract_id(), asset_id);
		abi(WrappedAsset,wrapped_asset.value).deposit{
			asset_id: asset_id.value,
			coins: amount
		}();
		let balance_after = balance_of(contract_id(), asset_id);
		DepositDetails {
			contract_id: contract_id().value,
			asset_value: asset_id.value,
			balance_before,
			balance_after
		}
	}
}