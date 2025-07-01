// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ZORGToken {
    string public name = "Zero Organization";
    string public symbol = "ZORG";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    bool public paused;

    address public owner;
    address public bridgeManager;
    address public router;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isDEX;

    // EIP-2612 permit
    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RouterUpdated(address indexed newRouter);
    event DEXUpdated(address indexed dex, bool allowed);
    event BridgeManagerUpdated(address indexed newManager);
    event TokensRescued(address indexed token, uint256 amount);
    event NativeRescued(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor() {
        owner = msg.sender;
        totalSupply = 1_000_000_000 * (10 ** decimals);
        balanceOf[owner] = totalSupply;
        emit Transfer(address(0), owner, totalSupply);

        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            chainId,
            address(this)
        ));
    }

    // --- ERC20 ---

    function transfer(address to, uint256 value) external whenNotPaused returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external whenNotPaused returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "Allowance too low");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "Zero address");
        require(balanceOf[from] >= value, "Insufficient balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    // --- Permit (EIP-2612) ---

    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        require(block.timestamp <= deadline, "Permit expired");
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                PERMIT_TYPEHASH,
                owner_, spender, value,
                nonces[owner_]++, deadline
            ))
        ));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered == owner_ && recovered != address(0), "Invalid signature");
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    // --- Admin: Ownable, Pause, Router, Bridge ---

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
        emit RouterUpdated(_router);
    }

    function setDEX(address _dex, bool allowed) external onlyOwner {
        isDEX[_dex] = allowed;
        emit DEXUpdated(_dex, allowed);
    }

    function setBridgeManager(address mgr) external onlyOwner {
        bridgeManager = mgr;
        emit BridgeManagerUpdated(mgr);
    }

    // --- Bridge Mint / Burn ---

    function bridgeMint(address to, uint256 amount) external {
        require(msg.sender == bridgeManager, "Not bridge manager");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external {
        require(msg.sender == bridgeManager, "Not bridge manager");
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    // --- UX Helpers ---

    function approveMaxIfNeeded(address spender, uint256 amount) external {
        if (allowance[msg.sender][spender] < amount) {
            allowance[msg.sender][spender] = type(uint256).max;
            emit Approval(msg.sender, spender, type(uint256).max);
        }
    }

    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool) {
        _transfer(msg.sender, to, value);
        require(to.code.length > 0, "Not a contract");
        (bool success,) = to.call(data);
        require(success, "Call failed");
        return true;
    }

    // --- Rescue ---

    function rescueToken(address token) external onlyOwner {
        require(token != address(this), "Cannot rescue self");
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner, bal);
        emit TokensRescued(token, bal);
    }

    function rescueNative() external onlyOwner {
        uint256 amt = address(this).balance;
        payable(owner).transfer(amt);
        emit NativeRescued(amt);
    }

    receive() external payable {}
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}
