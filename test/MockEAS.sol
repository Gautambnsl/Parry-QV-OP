// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockEAS {
    mapping(address => mapping(bytes32 => bool)) public hasAttestation;
    mapping(address => bytes32) public lastAttestationId;
    uint256 private nonce;

    function attest(
        AttestationRequest calldata request
    ) external payable returns (bytes32) {
        bytes32 attestationId = keccak256(
            abi.encodePacked(
                request.recipient,
                request.schema,
                nonce++
            )
        );
        
        hasAttestation[request.recipient][request.schema] = true;
        lastAttestationId[request.recipient] = attestationId;
        
        return attestationId;
    }

    struct AttestationRequest {
        address recipient;
        bytes32 schema;
        uint64 expirationTime;
        bytes32 refUID;
        bytes data;
        bool revocable;
    }
}