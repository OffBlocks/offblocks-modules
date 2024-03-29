import {buildModule} from "@nomicfoundation/hardhat-ignition/modules";

const FIFTEEN_SECONDS = 15;

const DelayedExecutionModule = buildModule("DelayedExecutionModule", (m) => {
  const owner = m.getParameter("owner");
  const minExecCooldown = m.getParameter("lockedAmount", FIFTEEN_SECONDS);

  const exec = m.contract("DelayedExecution", [owner, minExecCooldown]);

  return {exec};
});

export default DelayedExecutionModule;
