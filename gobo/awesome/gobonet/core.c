
#include <sys/ioctl.h>
#include <net/if.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <string.h>

#if LUA_VERSION_NUM < 502
#  define luaL_newlib(L,l) (lua_newtable(L), luaL_register(L,NULL,l))
#endif

int up_and_running(lua_State* L) {
   const char* iface = luaL_checkstring(L, 1);
   struct ifreq req;
   strncpy(req.ifr_name, iface, IFNAMSIZ-1);
   req.ifr_name[IFNAMSIZ-1] = '\0';
   int fd = socket(PF_INET6, SOCK_DGRAM, 0);
   int ok = ioctl(fd, SIOCGIFFLAGS, &req);
   if (ok != 0) {
      lua_pushstring(L, strerror(errno));
      lua_error(L);
   }
   lua_settop(L, 0);
   lua_pushboolean(L, req.ifr_flags & IFF_UP);
   lua_pushboolean(L, req.ifr_flags & IFF_RUNNING);
   return 2;
}

static const struct luaL_Reg core_lib[] = {
   {"up_and_running", up_and_running},
   {NULL, NULL},
};


int luaopen_gobo_awesome_gobonet_core(lua_State* L) {
   luaL_newlib (L, core_lib);
   return 1;
}
