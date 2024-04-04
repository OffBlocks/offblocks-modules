// Import the required functions
import {
  installModule,
  getModule,
  getAccount,
  getClient,
  getMFAValidator,
  getOwnableValidator,
} from "@rhinestone/module-sdk";
import {
  Address,
  Hash,
  concat,
  createClient,
  createPublicClient,
  encodeFunctionData,
  encodePacked,
  erc20Abi,
  fromBytes,
  fromHex,
  http,
  Hex,
  decodeFunctionData,
  parseAbiParameters,
  parseAbiParameter,
  encodeAbiParameters,
  decodeErrorResult,
} from "viem";
import {baseSepolia} from "viem/chains";
import {
  getAccountNonce,
  createSmartAccountClient,
  ENTRYPOINT_ADDRESS_V06,
  ENTRYPOINT_ADDRESS_V07,
} from "permissionless";
import {} from "permissionless/actions/pimlico";
import {
  createPimlicoBundlerClient,
  createPimlicoPaymasterClient,
} from "permissionless/clients/pimlico";
import {
  privateKeyToSimpleSmartAccount,
  toSmartAccount,
} from "permissionless/accounts";

import hre from "hardhat";
import {vars} from "hardhat/config";
import {encode} from "punycode";
import {decodeRevertReason} from "../test/utils/testUtils";

const CALLTYPE_SINGLE = "0x00";
const CALLTYPE_BATCH = "0x01";

const EXECTYPE_DEFAULT = "0x00";

const MODE_DEFAULT = "0x00000000";

function encodeSimpleBatch() {
  return encodePacked(
    ["bytes1", "bytes1", "bytes4", "bytes4", "bytes22"],
    [
      CALLTYPE_BATCH,
      EXECTYPE_DEFAULT,
      "0x00000000",
      MODE_DEFAULT,
      "0x00000000000000000000000000000000000000000000",
    ]
  );
}

function encodeSimpleSingle() {
  return encodePacked(
    ["bytes1", "bytes1", "bytes4", "bytes4", "bytes22"],
    [
      CALLTYPE_SINGLE,
      EXECTYPE_DEFAULT,
      "0x00000000",
      MODE_DEFAULT,
      "0x00000000000000000000000000000000000000000000",
    ]
  );
}

async function main() {
  // Create a client for the current network
  const client = getClient({rpcUrl: "https://sepolia.base.org"});

  // Create the module object if you are using a custom module
  //   const module = getModule({
  //     module: moduleAddress,
  //     data: initData,
  //     type: moduleType,
  //   });

  // Or use one of the existing modules
  const ownerModule = getOwnableValidator({
    ownerAddress: "0xfe9a6492dD767525D46b0F69c5c90861f2819b5C",
  });

  // Create the account object
  //   const account = getAccount({
  //     address: "0xa7BcAdf91ECfB7Eb7908736A658dd821a9D387d8",
  //     type: "erc7579-implementation",
  //   });

  // Get the executions required to install the module
  //   const executions = await installModule({
  //     client,
  //     account,
  //     module,
  //   });

  // Install the module on your account, using your existing account SDK
  const apiKey = "dbe79c74-dd80-4444-8989-6cf798304b8e";
  const paymasterUrl = `https://api.pimlico.io/v2/84532/rpc?apikey=${apiKey}`;

  const privateKey = `0x${vars.get("SEPOLIA_PRIVATE_KEY")}` as Hex;

  const publicClient = createPublicClient({
    transport: http("https://sepolia.base.org"),
  });

  const paymasterClient = createPimlicoPaymasterClient({
    transport: http(paymasterUrl),
    entryPoint: ENTRYPOINT_ADDRESS_V07,
  });

  const owner = "0xfe9a6492dD767525D46b0F69c5c90861f2819b5C";
  const address = "0x66C8de5b72CaBaDcF612B89Dd3DAfdb247FB29B7";
  const delayedExecution = "0x7E320a0dbFA49bd0B5bcA996E144d6c2d5D5462C";
  const fiatPayment = "0x76c389a9B8e958e5554385Aa61C7b67cED4C359C";
  const USDC = "0xCe359Fe4fbbd25c2Ac36549852e175A486AD8428";

  const msaAdvanced = await hre.viem.getContractAt("MSAAdvanced", address);

  const smartAccount = toSmartAccount({
    ...(await privateKeyToSimpleSmartAccount(publicClient, {
      privateKey,
      entryPoint: ENTRYPOINT_ADDRESS_V07, // global entrypoint
      factoryAddress: "0xFf81C1C2075704D97F6806dE6f733d6dAF20c9c6",
      address,
    })),
    encodeCallData: async (args) => {
      if (Array.isArray(args)) {
        const argsArray = (
          args as {
            to: Address;
            value: bigint;
            data: Hex;
          }[]
        ).map((arg) => ({
          target: arg.to,
          value: arg.value,
          callData: arg.data,
        }));

        const encodedBatch = encodeAbiParameters(
          parseAbiParameters(
            "(address target,uint256 value,bytes callData)[] executions"
          ),
          [argsArray]
        );

        return encodeFunctionData({
          abi: msaAdvanced.abi,
          functionName: "execute",
          args: [encodeSimpleBatch(), encodedBatch],
        });
      } else {
        const encodedSingle = encodePacked(
          ["address", "uint256", "bytes"],
          [args.to, args.value, args.data]
        );

        return encodeFunctionData({
          abi: msaAdvanced.abi,
          functionName: "execute",
          args: [encodeSimpleSingle(), encodedSingle],
        });
      }
    },
  });

  const bundlerUrl = `https://api.pimlico.io/v2/base-sepolia/rpc?apikey=${apiKey}`;

  const bundlerClient = createPimlicoBundlerClient({
    transport: http(bundlerUrl),
    entryPoint: ENTRYPOINT_ADDRESS_V07,
  });

  const smartAccountClient = createSmartAccountClient({
    account: smartAccount,
    entryPoint: ENTRYPOINT_ADDRESS_V07,
    chain: baseSepolia,
    bundlerTransport: http(bundlerUrl),
    middleware: {
      gasPrice: async () => {
        return (await bundlerClient.getUserOperationGasPrice()).fast;
      },
      sponsorUserOperation: paymasterClient.sponsorUserOperation,
    },
  });

  const exec = await hre.viem.getContractAt(
    "DelayedExecution",
    delayedExecution
  );

  const payment = await hre.viem.getContractAt("FiatPayment", fiatPayment);

  const transfer = encodeFunctionData({
    abi: erc20Abi,
    functionName: "transfer",
    args: [owner, BigInt(19000000)],
  });

  const initExecution = encodeFunctionData({
    abi: exec.abi,
    functionName: "initExecution",
    args: [USDC, BigInt(0), transfer],
  });

  const initTxData = encodeFunctionData({
    abi: exec.abi,
    functionName: "execute",
    args: [address, delayedExecution, BigInt(0), initExecution],
  });

  const txData = encodeFunctionData({
    abi: exec.abi,
    functionName: "execute",
    args: [address, USDC, BigInt(0), transfer],
  });

  const txHashInit = await smartAccountClient.sendTransaction({
    to: delayedExecution,
    data: initTxData,
    nonce:
      (BigInt("0x652a10b050d7572F2B7563f7a77e79472B5160FD") << BigInt(96)) +
      BigInt(4),
  });

  console.log("Init transaction hash:", txHashInit);

  const reserve = encodeFunctionData({
    abi: payment.abi,
    functionName: "reserve",
    args: [USDC, [BigInt(1000000)], [owner]],
  });

  const txHashReserve = await smartAccountClient.sendTransaction({
    to: fiatPayment,
    data: reserve,
    nonce:
      (BigInt("0x652a10b050d7572F2B7563f7a77e79472B5160FD") << BigInt(96)) +
      BigInt(5),
  });

  console.log("Reserve transaction hash:", txHashReserve);

  await new Promise((f) => setTimeout(f, 30000));

  const txHash = await smartAccountClient.sendTransaction({
    to: delayedExecution,
    data: txData,
    nonce:
      (BigInt("0x652a10b050d7572F2B7563f7a77e79472B5160FD") << BigInt(96)) +
      BigInt(6),
  });

  console.log("Transaction hash:", txHash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
