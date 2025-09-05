#pragma version ^0.4.3
#pragma optimize gas
#pragma evm-version prague

"""
@title CryptoFromPoolZkBtc
@notice Price oracle for pools which contain cryptos and crvUSD, with Chainlink optionally included as bound. This is NOT suitable for minted crvUSD - only for lent out
@author Curve.Fi, Lightec Labs
@license MIT
"""


interface Pool:
    def price_oracle() -> uint256: view  # Universal method!
    def totalSupply() -> uint256: view   # when the total supply of the underlying pool is below certain level, we use Chainlink price as bounds.


struct ChainlinkAnswer:
    round_id: uint80
    answer: int256
    started_at: uint256
    updated_at: uint256
    answered_in_round: uint80


interface ChainlinkAggregator:
    def latestRoundData() -> ChainlinkAnswer: view
    def decimals() -> uint8: view


event SetUseChainklink:
    do_it: bool


event SetAdmin:
    admin: address


POOL: public(immutable(Pool))

SUPPLY_THESHOLD: constant(uint256) = 9600 * 10**18 # about 6.5M crvUSD as of Aug 2025

BOUND_SIZE: constant(uint256) = 15 * 10**15 # 1.5%

CHAINLINK_AGGREGATOR_BTC: public(immutable(ChainlinkAggregator))
CHAINLINK_PRICE_PRECISION_BTC: immutable(uint256)
CHAINLINK_STALE_THRESHOLD: constant(uint256) = 86400

use_chainlink: public(bool)
admin: public(address)


@deploy
def __init__(
        pool: Pool,
        chainlink_aggregator_btc: ChainlinkAggregator,
    ):
    POOL = pool
    CHAINLINK_AGGREGATOR_BTC = chainlink_aggregator_btc
    CHAINLINK_PRICE_PRECISION_BTC = 10**convert(staticcall chainlink_aggregator_btc.decimals(), uint256)
    self.use_chainlink = True
    self.admin = msg.sender


@internal
@view
def _raw_price() -> uint256:
    p_collateral: uint256 = 10**18 # price oracle must return price in 10**18
    p_borrowed: uint256 = staticcall POOL.price_oracle()
    price: uint256 = p_collateral * 10**18 // p_borrowed # price oracle returns in 10**18

    # Limit BTC price
    if self.use_chainlink or staticcall POOL.totalSupply() < SUPPLY_THESHOLD:
        chainlink_lrd: ChainlinkAnswer = staticcall CHAINLINK_AGGREGATOR_BTC.latestRoundData()
        if block.timestamp - min(chainlink_lrd.updated_at, block.timestamp) <= CHAINLINK_STALE_THRESHOLD:
            chainlink_p: uint256 = convert(chainlink_lrd.answer, uint256) * 10**18 // CHAINLINK_PRICE_PRECISION_BTC
            lower: uint256 = chainlink_p * (10**18 - BOUND_SIZE) // 10**18
            upper: uint256 = chainlink_p * (10**18 + BOUND_SIZE) // 10**18
            price = min(max(price, lower), upper)

    return price


@external
@view
def price() -> uint256:
    return self._raw_price()


@external
def price_w() -> uint256:
    return self._raw_price()


@external
@nonreentrant
def set_use_chainlink(_do_it: bool):
    assert msg.sender == self.admin
    self.use_chainlink = _do_it
    log SetUseChainklink(do_it=_do_it)


@external
@nonreentrant
def set_admin(_admin: address):
    assert msg.sender == self.admin
    self.admin = _admin
    log SetAdmin(admin=_admin)
