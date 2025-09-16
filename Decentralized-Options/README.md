# STX Decentralized Options Exchange

A comprehensive decentralized marketplace for STX options trading with automated settlement, built on the Stacks blockchain.

## Overview

The STX Decentralized Options Exchange is a smart contract that enables users to create, trade, and exercise options contracts on STX tokens. The platform supports both call and put options with full on-chain execution and automated settlement mechanisms.

## Key Features

### Core Functionality
- **Option Creation**: Writers can create new call and put option contracts
- **Option Trading**: Seamless transfer of option ownership between users
- **Option Exercise**: Full exercise functionality for both call and put options
- **Automated Settlement**: Expired options are automatically settled with collateral release

### Risk Management
- **Collateral Management**: Robust collateral tracking and locking mechanisms
- **Input Validation**: Comprehensive validation for all parameters
- **Platform Limits**: Built-in limits for strike prices, contract sizes, and expiration periods
- **Emergency Controls**: Admin functions for pausing trading and emergency shutdown

### Fee Structure
- **Platform Fees**: Configurable fee structure with basis point precision
- **Fee Distribution**: Automated fee collection and distribution

## Contract Architecture

### Data Structures

**Options Ledger**: Primary registry tracking all option contracts with complete metadata
- Option creator and current holder
- Strike price, premium, and expiration details
- Contract type, status, and size information
- Collateral tracking and lock status

**Collateral Balances**: User collateral management
- Total locked amounts per user
- Available withdrawal balances
- Real-time collateral tracking

**Market Price Feeds**: Price data for settlement
- Block-based price updates
- Timestamp and reporter tracking

### Option Types

**Call Options (Type 1)**
- Gives holder the right to buy STX at strike price
- Writer provides collateral equal to contract size × strike price
- Exercise requires payment of strike price × contract size

**Put Options (Type 2)**
- Gives holder the right to sell STX at strike price  
- Writer provides collateral equal to contract size × strike price
- Exercise results in payout from collateral to holder

### Option Status
- **Active (1)**: Option is live and can be exercised
- **Exercised (2)**: Option has been exercised
- **Expired (3)**: Option has expired without exercise

## Platform Limits

**Strike Price Limits**
- Minimum: 0.001 STX (1,000 micro-STX)
- Maximum: 100 STX (100,000,000 micro-STX)

**Contract Size Limits**
- Minimum: 1 unit
- Maximum: 1,000,000 units

**Expiration Limits**
- Minimum: 144 blocks (approximately 24 hours)
- Maximum: 52,560 blocks (approximately 1 year)

**Platform Fees**
- Default: 1% (100 basis points)
- Maximum: 10% (1,000 basis points)

## Core Functions

### User Functions

#### Collateral Management
```clarity
(deposit-trading-collateral (amount uint))
```
Deposit STX tokens as collateral for writing options.

```clarity
(withdraw-available-collateral (amount uint))
```
Withdraw available collateral not currently locked in active positions.

#### Option Creation
```clarity
(create-new-option-contract 
  (strike-price uint)
  (premium uint)
  (expiration-block uint)
  (option-type uint)
  (contract-size uint))
```
Create a new option contract with specified parameters. Requires sufficient collateral.

#### Option Trading
```clarity
(purchase-option-contract (option-id uint))
```
Purchase an option from its creator, paying the premium minus platform fees.

```clarity
(transfer-option-ownership (option-id uint) (new-holder principal))
```
Transfer option ownership to another user.

#### Option Exercise
```clarity
(exercise-call-option-contract (option-id uint))
```
Exercise a call option by paying the strike price.

```clarity
(exercise-put-option-contract (option-id uint))
```
Exercise a put option to receive payout from collateral.

#### Settlement
```clarity
(settle-expired-option-contract (option-id uint))
```
Settle an expired option and release locked collateral back to the writer.

### Read-Only Functions

```clarity
(fetch-option-contract-details (option-id uint))
```
Get complete details of a specific option contract.

```clarity
(fetch-account-collateral-info (account principal))
```
Get collateral information for a specific account.

```clarity
(fetch-platform-configuration)
```
Get current platform configuration and status.

### Admin Functions

```clarity
(pause-trading-operations)
(resume-trading-operations)
```
Control trading operations during maintenance or emergencies.

```clarity
(update-platform-fee-rate (new-rate uint))
```
Update platform fee structure (admin only).

```clarity
(activate-emergency-shutdown)
```
Activate emergency shutdown mode (admin only).

## Error Codes

- `ERR-UNAUTHORIZED-ACCESS (1000)`: Insufficient permissions
- `ERR-INVALID-OPTION-IDENTIFIER (1001)`: Invalid option ID
- `ERR-OPTION-EXPIRED (1002)`: Option has expired
- `ERR-OPTION-ALREADY-EXERCISED (1003)`: Option already exercised
- `ERR-INSUFFICIENT-BALANCE (1004)`: Insufficient token balance
- `ERR-INVALID-EXPIRATION (1005)`: Invalid expiration parameters
- `ERR-INVALID-STRIKE-PRICE (1006)`: Strike price outside limits
- `ERR-NOT-OPTION-HOLDER (1007)`: Not the option holder
- `ERR-INVALID-PREMIUM (1008)`: Invalid premium amount
- `ERR-INVALID-CONTRACT-SIZE (1009)`: Contract size outside limits
- `ERR-UNSUPPORTED-OPTION-TYPE (1010)`: Invalid option type
- `ERR-INSUFFICIENT-COLLATERAL (1011)`: Insufficient collateral
- `ERR-NOT-OPTION-WRITER (1012)`: Not the option writer
- `ERR-OPTION-NOT-FOUND (1013)`: Option does not exist
- `ERR-CONTRACT-PAUSED (1014)`: Contract operations paused
- `ERR-INVALID-PRICE (1015)`: Invalid price parameter
- `ERR-COLLATERAL-LOCKED (1016)`: Collateral is locked

## Usage Examples

### Creating a Call Option
1. Deposit sufficient collateral using `deposit-trading-collateral`
2. Create option with `create-new-option-contract` specifying:
   - Strike price in micro-STX
   - Premium amount
   - Expiration block height
   - Option type (1 for call)
   - Contract size

### Buying and Exercising Options
1. Find available options using `fetch-option-contract-details`
2. Purchase with `purchase-option-contract`
3. Exercise before expiration using `exercise-call-option-contract` or `exercise-put-option-contract`

### Collateral Management
1. Deposit collateral before writing options
2. Monitor locked vs available amounts
3. Withdraw available collateral when not needed

## Security Considerations

- All inputs are validated before processing
- Collateral is locked during option lifetime
- Emergency shutdown capabilities for critical situations
- Automated settlement prevents stuck collateral
- Platform limits prevent extreme parameter values

## Technical Requirements

- Stacks blockchain environment
- Clarity smart contract runtime
- STX token transfers capability