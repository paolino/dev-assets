{
  description = "Shared development and release assets";

  outputs = { self }: {
    lib = import ./nix/lib;
  };
}
