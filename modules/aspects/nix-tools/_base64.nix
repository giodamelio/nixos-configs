# toBase64 vendored from https://github.com/3nol/nix-base64 (base64/default.nix).
#
# MIT License
#
# Copyright (c) 2025 Leon Wenzler
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
{lib}: let
  ithSlice = size: list: i:
    lib.sublist (i * size) size list;

  digitsOf = base: pows: i:
    map (p: lib.mod (i / p) base) pows;

  foldBase = base: builtins.foldl' (acc: d: acc * base + d) 0;

  charToBytes = lib.strings.charToInt;

  lookup = lib.stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  sextetToChar = builtins.elemAt lookup;

  bytesToInt = foldBase 256;

  intToSextets = digitsOf 64 [
    (64 * 64 * 64)
    (64 * 64)
    64
    1
  ];
in {
  toBase64 = str:
    if builtins.stringLength str == 0
    then ""
    else let
      bytes = map charToBytes (lib.stringToCharacters str);
      numTriplets = (builtins.stringLength str) / 3;
      tripletAt = ithSlice 3 bytes;

      convertTriplet = slice: lib.concatMapStrings sextetToChar (intToSextets (bytesToInt slice));
      convertLastTriplet = slice: let
        len = builtins.length slice;
        slice' = slice ++ lib.replicate (3 - len) 0;
        encoded = lib.concatMapStrings sextetToChar (intToSextets (bytesToInt slice'));
      in
        lib.optionalString (0 < len && len < 3) (
          builtins.substring 0 (len + 1) encoded + lib.strings.replicate (3 - len) "="
        );

      heads = builtins.genList (i: convertTriplet (tripletAt i)) numTriplets;
      tail = convertLastTriplet (tripletAt numTriplets);
    in
      lib.concatStrings (heads ++ [tail]);
}
