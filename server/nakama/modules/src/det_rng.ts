// Générateur déterministe xorshift32, identique bit à bit à client/src/gameplay/det_rng.gd.
class DetRng {
  state: number;
  constructor(seed: number) {
    this.state = seed >>> 0;
    if (this.state === 0) this.state = 0x9e3779b9;
  }
  nextU32(): number {
    let x = this.state;
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    this.state = x;
    return x;
  }
  rangeInt(low: number, high: number): number {
    return low + (this.nextU32() % (high - low + 1));
  }
}
