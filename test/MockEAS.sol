// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockEAS {
    mapping(address => mapping(bytes32 => bool)) public hasAttestation;
    mapping(address => bytes32) public lastAttestationId;
    uint256 private nonce;

    struct AttestationRequestData {
        address recipient;
        uint64 expirationTime;
        bool revocable;
        bytes32 refUID;
        bytes data;
        uint256 value;
    }

    struct AttestationRequest {
        bytes32 schema;
        AttestationRequestData data;
    }

    function attest(
        AttestationRequest calldata request
    ) external payable returns (bytes32) {
        bytes32 attestationId = keccak256(
            abi.encodePacked(
                request.data.recipient,
                request.schema,
                nonce++
            )
        );
        
        hasAttestation[request.data.recipient][request.schema] = true;
        lastAttestationId[request.data.recipient] = attestationId;
        
        return attestationId;
    }
}