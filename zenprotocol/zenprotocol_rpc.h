#include <miner.h>

char* zenprotocol_getheader(CURL *curl, struct pool_infos *pool);
bool zenprotocol_work_decode(const char *hexdata, struct work *work);
bool zenprotocol_submit(CURL *curl, struct pool_infos *pool, struct work *work);
