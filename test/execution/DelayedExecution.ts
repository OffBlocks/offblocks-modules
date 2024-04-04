import {
  loadFixture,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {expect} from "chai";
import hre from "hardhat";
import {
  encodeTransfer,
  encodeExecuteFromExecutor,
  HashZero,
} from "../utils/testUtils";
import {ZeroHash, solidityPacked} from "ethers";

describe("DelayedExecution", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployDelayedExecutionFixture() {
    const FIFTEEN_SECONDS = 15;

    // Contracts are deployed using the first signer/account by default
    const [owner, other] = await hre.ethers.getSigners();

    const coder = hre.ethers.AbiCoder.defaultAbiCoder();

    const DelayedExecution = await hre.ethers.getContractFactory(
      "DelayedExecution"
    );
    const exec = await DelayedExecution.deploy(owner, FIFTEEN_SECONDS);

    return {exec, owner, other, coder};
  }

  async function deployBootstrapFixture() {
    const Bootstrap = await hre.ethers.getContractFactory("Bootstrap");
    const bootstrap = await Bootstrap.deploy();

    return {bootstrap};
  }

  async function deployFactoryFixture() {
    const MSAAdvanced = await hre.ethers.getContractFactory("MSAAdvanced");
    const account = await MSAAdvanced.deploy();

    const MSAFactory = await hre.ethers.getContractFactory("MSAFactory");
    const factory = await MSAFactory.deploy(await account.getAddress());

    return {factory};
  }

  async function deployMockTokenFixture() {
    const MockToken = await hre.ethers.getContractFactory("MockToken");
    const token = await MockToken.deploy("Mock Token", "MOCK", 6, 1000000000);

    return {token};
  }

  describe("Deployment", function () {
    it("Should set the right minExecCooldown", async function () {
      const FIFTEEN_SECONDS = 15;

      const {exec} = await loadFixture(deployDelayedExecutionFixture);

      expect(await exec.minExecCooldown()).to.equal(FIFTEEN_SECONDS);
    });

    it("Should set the right owner", async function () {
      const {exec, owner} = await loadFixture(deployDelayedExecutionFixture);

      expect(await exec.owner()).to.equal(owner.address);
    });
  });

  describe("Configuration", function () {
    it("Should set the right minExecCooldown after update", async function () {
      const THIRTY_SECONDS = 30;

      const {exec} = await loadFixture(deployDelayedExecutionFixture);

      await exec.setMinExecCooldown(THIRTY_SECONDS);

      expect(await exec.minExecCooldown()).to.equal(THIRTY_SECONDS);
    });

    it("Only owner can update minExecCooldown", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, other} = await loadFixture(deployDelayedExecutionFixture);

      // We use lock.connect() to send a transaction from another account
      await expect(exec.connect(other).setMinExecCooldown(THIRTY_SECONDS)).to.be
        .reverted;
    });

    it("Should return isInitialized == true after installation", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      expect(await exec.isInitialized(other)).to.equal(true);
    });

    it("Should revert on installation if cooldown is lower than configured", async function () {
      const TEN_SECONDS = 10;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await expect(
        exec.connect(other).onInstall(coder.encode(["uint256"], [TEN_SECONDS]))
      ).to.be.reverted;
    });

    it("Should return isInitialized == false before installation", async function () {
      const {exec, other} = await loadFixture(deployDelayedExecutionFixture);

      expect(await exec.isInitialized(other)).to.equal(false);
    });

    it("Should return isInitialized == false after un-installation", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      await exec
        .connect(other)
        .onUninstall(coder.encode(["uint256"], [THIRTY_SECONDS]));

      expect(await exec.isInitialized(other)).to.equal(false);
    });
  });

  describe("Execution", function () {
    it("Should revert initExecution if exec is not initialized for the account", async function () {
      const {exec, other} = await loadFixture(deployDelayedExecutionFixture);

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await expect(
        exec.connect(other).initExecution(await token.getAddress(), 0, transfer)
      ).to.be.revertedWithCustomError(exec, "UnauthorizedAccess");
    });

    it("Should enqueue execution on initExecution if exec is initialized for the account", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await expect(
        exec.connect(other).initExecution(await token.getAddress(), 0, transfer)
      ).to.emit(exec, "ExecutionInitiated");

      expect(await exec.hasPendingExecution(other)).to.be.true;
    });

    it("Should revert on duplicate initExecution if previous execution did not complete", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await expect(
        exec.connect(other).initExecution(await token.getAddress(), 0, transfer)
      ).to.emit(exec, "ExecutionInitiated");

      await expect(
        exec.connect(other).initExecution(await token.getAddress(), 0, transfer)
      ).to.be.revertedWithCustomError(exec, "ExecutionNotAuthorized");
    });

    it("Should skip execution on skipExecution", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer);

      await expect(
        exec.connect(other).skipExecution(await token.getAddress(), 0, transfer)
      ).to.emit(exec, "ExecutionSkipped");

      expect(await exec.hasPendingExecution(other)).to.be.false;
    });

    it("Should enqueue duplicate execution on initExecution if previous execution was skipped", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer);

      await exec
        .connect(other)
        .skipExecution(await token.getAddress(), 0, transfer);

      await expect(
        exec.connect(other).initExecution(await token.getAddress(), 0, transfer)
      ).to.emit(exec, "ExecutionInitiated");
    });

    it("Should revert on skipExecution if skipping not initiated execution", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer3 = encodeTransfer(await token.getAddress(), 300000);
      const transfer5 = encodeTransfer(await token.getAddress(), 500000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer3);

      await expect(
        exec
          .connect(other)
          .skipExecution(await token.getAddress(), 0, transfer5)
      ).to.be.revertedWithCustomError(exec, "ExecutionHashNotFound");
    });

    it("Should revert on skipExecution if skipping is out of order", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer3 = encodeTransfer(await token.getAddress(), 300000);
      const transfer5 = encodeTransfer(await token.getAddress(), 500000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer3);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer5);

      await expect(
        exec
          .connect(other)
          .skipExecution(await token.getAddress(), 0, transfer5)
      ).to.be.revertedWithCustomError(exec, "ExecutionNotAuthorized");
    });

    it("Should revert on executeFromExecutor if execution was not initiated", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      // zero hash (empty bytes32) corresponds to default single execution mode
      const execute = encodeExecuteFromExecutor(
        HashZero,
        await token.getAddress(),
        0,
        transfer
      );

      await expect(
        exec.connect(other).preCheck(other, execute)
      ).to.be.revertedWithCustomError(exec, "ExecutionHashNotFound");
    });

    it("Should revert on executeFromExecutor if execution is out of order", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer3 = encodeTransfer(await token.getAddress(), 300000);
      const transfer5 = encodeTransfer(await token.getAddress(), 500000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer3);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer5);

      // zero hash (empty bytes32) corresponds to default single execution mode
      const execute = encodeExecuteFromExecutor(
        HashZero,
        await token.getAddress(),
        0,
        transfer5
      );

      await expect(
        exec.connect(other).preCheck(other, execute)
      ).to.be.revertedWithCustomError(exec, "ExecutionNotAuthorized");
    });

    it("Should revert on executeFromExecutor if cooldown period not passed", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer);

      // zero hash (empty bytes32) corresponds to default single execution mode
      const execute = encodeExecuteFromExecutor(
        HashZero,
        await token.getAddress(),
        0,
        transfer
      );

      await expect(
        exec.connect(other).preCheck(other, execute)
      ).to.be.revertedWithCustomError(exec, "ExecutionNotAuthorized");
    });

    it("Should submit execution on executeFromExecutor", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      await exec
        .connect(other)
        .onInstall(
          coder.encode(["uint256", "address[]"], [THIRTY_SECONDS, []])
        );

      const {token} = await loadFixture(deployMockTokenFixture);

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      await exec
        .connect(other)
        .initExecution(await token.getAddress(), 0, transfer);

      const unlockTime = (await time.latest()) + THIRTY_SECONDS;

      await time.increaseTo(unlockTime);

      // zero hash (empty bytes32) corresponds to default single execution mode
      const execute = encodeExecuteFromExecutor(
        HashZero,
        await token.getAddress(),
        0,
        transfer
      );

      await expect(exec.connect(other).preCheck(other, execute)).to.emit(
        exec,
        "ExecutionSubmitted"
      );
    });

    it("Should submit whitelisted execution on executeFromExecutor without delay", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, other} = await loadFixture(
        deployDelayedExecutionFixture
      );

      const {token} = await loadFixture(deployMockTokenFixture);

      await exec
        .connect(other)
        .onInstall(
          coder.encode(
            ["uint256", "address[]"],
            [THIRTY_SECONDS, [other.address]]
          )
        );

      const transfer = encodeTransfer(await token.getAddress(), 1000000);

      // zero hash (empty bytes32) corresponds to default single execution mode
      const execute = encodeExecuteFromExecutor(
        HashZero,
        await token.getAddress(),
        0,
        transfer
      );

      await expect(exec.connect(other).preCheck(other, execute)).to.not.be
        .reverted;
    });
  });

  describe("End-to-end", function () {
    it("Should submit execution on execute", async function () {
      const THIRTY_SECONDS = 30;

      const {exec, coder, owner} = await loadFixture(
        deployDelayedExecutionFixture
      );

      const {bootstrap} = await loadFixture(deployBootstrapFixture);
      const {factory} = await loadFixture(deployFactoryFixture);

      const initCode = await bootstrap._getInitMSACalldata(
        [],
        [
          {
            module: await exec.getAddress(),
            data: coder.encode(["uint256", "address[]"], [15, []]),
          },
        ],
        {
          module: await exec.getAddress(),
          data: coder.encode(["uint256", "address[]"], [15, []]),
        },
        []
      );

      await factory.connect(owner).createAccount(ZeroHash, initCode);

      const address = await factory.connect(owner).getFunction("getAddress")(
        ZeroHash,
        initCode
      );

      const {token} = await loadFixture(deployMockTokenFixture);

      expect(await token.connect(owner).mint(address, 10000000)).not.to.be
        .reverted;

      await expect(
        exec
          .connect(owner)
          .execute(
            address,
            await exec.getAddress(),
            0,
            exec.interface.encodeFunctionData("initExecution", [
              await token.getAddress(),
              0,
              encodeTransfer(await owner.getAddress(), 1000000),
            ])
          )
      ).to.emit(exec, "ExecutionInitiated");

      const unlockTime = (await time.latest()) + THIRTY_SECONDS;
      await time.increaseTo(unlockTime);

      await expect(
        exec.execute(
          address,
          await token.getAddress(),
          0,
          encodeTransfer(await owner.getAddress(), 1000000)
        )
      ).to.emit(exec, "ExecutionSubmitted");
    });
  });
});
