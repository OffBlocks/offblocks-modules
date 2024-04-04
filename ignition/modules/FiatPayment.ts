import {buildModule} from "@nomicfoundation/hardhat-ignition/modules";

const FiatPaymentModule = buildModule("FiatPaymentModule", (m) => {
  const owner = m.getParameter("owner");
  const USDC = m.getParameter("USDC");

  const fiatPayment = m.contract("FiatPayment", [owner, [USDC]]);

  return {fiatPayment};
});

export default FiatPaymentModule;
