{
  routeGroups.fcm.routes = [
    "192.168.2.0/24"
    "192.168.3.0/24"
    "192.168.6.0/24"
    "192.168.7.0/24"
    "192.168.8.0/24"
  ];

  routers = {
    medo = {
      owner = "cloud";
      tag = "tag:cloud-exit";
      exitNode = true;
      routeGroups = [ ];
    };
    medo-test = {
      owner = "cloud";
      tag = "tag:cloud-exit";
      exitNode = true;
      routeGroups = [ ];
    };
    fcmutils = {
      owner = "fcm";
      tag = "tag:fcmutils-router";
      exitNode = true;
      routeGroups = [ "fcm" ];
    };
    fcmbuilder = {
      owner = "fcm";
      tag = "tag:fcmbuilder-router";
      exitNode = true;
      routeGroups = [ "fcm" ];
    };
    fcmutils-test = {
      owner = "fcm";
      tag = "tag:fcmutils-test-router";
      exitNode = true;
      routeGroups = [ ];
    };
  };
}
