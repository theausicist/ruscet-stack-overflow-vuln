// SPDX-License-Identifier: Apache-2.0
contract;

use std::auth::msg_sender;

abi Caller {
	fn call_callee(contract_id: ContractId) -> (bool, bool);
}

abi Callee {
	fn get_sender() -> (bool, bool);
}

impl Callee for Contract {
	fn get_sender() -> (bool, bool) { (false, false) }
}
 
impl Caller for Contract {
	// (address, contract)
	fn call_callee(contr_id: ContractId) -> (bool, bool) {
		let callee = abi(Callee, contr_id.value);

		callee.get_sender()
	}
}
