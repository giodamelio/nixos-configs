_: _: {
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = ["*"];
      settings = {
        main = {
          # Make capslock be control when held and escape when tapped
          capslock = "overload(control, esc)";

          # Make esc be capslock
          esc = "capslock";
        };
      };
    };
  };
}
