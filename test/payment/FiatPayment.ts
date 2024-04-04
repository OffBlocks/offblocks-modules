import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import hre from "hardhat";

describe("FiatPayment", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployFiatPaymentFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner] = await hre.ethers.getSigners();

    const coder = hre.ethers.AbiCoder.defaultAbiCoder();

    const MockToken = await hre.ethers.getContractFactory("MockToken");
    const token = await MockToken.deploy("Mock Token", "MOCK", 6, 1000000000);

    const FiatPayment = await hre.ethers.getContractFactory("FiatPayment");
    const payment = await FiatPayment.deploy(owner, [await token.getAddress()]);

    return {payment, owner, token, coder};
  }

  describe("Configuration", function () {
    it("Should return isInitialized == true after installation", async function () {
      const {payment, coder, token} = await loadFixture(
        deployFiatPaymentFixture
      );

      await payment.onInstall(
        coder.encode(
          ["address[]", "uint256[]", "uint256[]"],
          [[await token.getAddress()], [10000000], [100000000]]
        )
      );
    });
  });
});
