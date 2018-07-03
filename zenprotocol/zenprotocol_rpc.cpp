#include <ccminer-config.h>

#include <string>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <inttypes.h>
#include <unistd.h>
#include <math.h>
#include <sys/time.h>
#include <time.h>
#include <signal.h>
#include <curl/curl.h>
#include <miner.h>
#include <jansson.h>

#include "zenprotocol_rpc.h"

static bool zenprotocol_debug_diff = false;

extern int share_result(int result, int pooln, double sharediff, const char *reason);

/* compute nbits to get the network diff */
static void calc_network_diff(struct work *work)
{
	uint32_t nbits = work->data[11]; // unsure if correct
	uint32_t bits = (nbits & 0xffffff);
	int16_t shift = (swab32(nbits) & 0xff); // 0x1c = 28

	uint64_t diffone = 0x0000FFFF00000000ull;
	double d = (double)0x0000ffff / (double)bits;

	for (int m=shift; m < 29; m++) d *= 256.0;
	for (int m=29; m < shift; m++) d /= 256.0;
	if (zenprotocol_debug_diff)
		applog(LOG_DEBUG, "net diff: %f -> shift %u, bits %08x", d, shift, bits);

	net_diff = d;
}

// ---- ZENPROTOCOL LONGPOLL --------------------------------------------------------------------------------

struct data_buffer {
	void *buf;
	size_t len;
};

static size_t zenprotocol_data_cb(const void *ptr, size_t size, size_t nmemb,
			  void *user_data)
{
	struct data_buffer *db = (struct data_buffer *)user_data;
	size_t len = size * nmemb;
	size_t oldlen, newlen;
	void *newmem;
	static const uchar zero = 0;

	oldlen = db->len;
	newlen = oldlen + len;

	newmem = realloc(db->buf, newlen + 1);
	if (!newmem)
		return 0;

	db->buf = newmem;
	db->len = newlen;
	memcpy((char*)db->buf + oldlen, ptr, len);
	memcpy((char*)db->buf + newlen, &zero, 1);	/* null terminate */

	return len;
}

char* zenprotocol_getheader(CURL *curl, struct pool_infos *pool)
{
	char curl_err_str[CURL_ERROR_SIZE] = { 0 };
	struct data_buffer all_data = { 0 };
	struct curl_slist *headers = NULL;
	char data[256] = { 0 };
	char url[512];

        snprintf(url, 512, "%s/blockchain/blocktemplate", pool->url);

	if (opt_protocol)
		curl_easy_setopt(curl, CURLOPT_VERBOSE, 1);
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_POST, 0);
	curl_easy_setopt(curl, CURLOPT_ENCODING, "");
	curl_easy_setopt(curl, CURLOPT_FAILONERROR, 0);
	curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1);
	curl_easy_setopt(curl, CURLOPT_TCP_NODELAY, 1);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, opt_timeout);
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_err_str);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, zenprotocol_data_cb);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &all_data);

	headers = curl_slist_append(headers, "Content-Type: application/json");
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

	int rc = curl_easy_perform(curl);
	if (rc && strlen(curl_err_str)) {
		applog(LOG_WARNING, "%s", curl_err_str);
	}

        if (opt_protocol)
          applog(LOG_DEBUG, "received %d bytes: %s", (int) all_data.len, all_data.buf);

	curl_slist_free_all(headers);

	return rc == 0 && all_data.len ? strdup((char*)all_data.buf) : NULL;
}

bool zenprotocol_work_decode(const char *data, struct work *work)
{
  if (!work) {
    applog(LOG_ERR, "NULL work");
    return false;
  }

	//	{"header":"00000000000000176a90a6182401c6d05ff5f08c0371f9f8a69ae9416643a9f2b8df0b7d000008547c3613be3c56bf94bc7c893b64d2155d9318523b679e029ce7a055ac5257398200000164472a2bab1d24579900000000000000000000000000000000","body":"03c42b88ef4e72fd9eed55a9d56e70061a6c2fe98e90e35b27de506445c9723115aa499ca7b12aa5a881aafc26a797bc25abf1445d4c609efe5e7c90adf2541e4cc12148a22b436f4847e64ef69b61800dc7c0ba7865ffb1c973ebcb45c6095c920100000000000106240000085436a8b7fd61c0a963a438ceec0cb165c960cf16dcc2383367420820fb25d193e1007e0000012a05ffd60000","target":"0000002457990000000000000000000000000000000000000000000000000000","parent":"000000176a90a6182401c6d05ff5f08c0371f9f8a69ae9416643a9f2b8df0b7d","blockNumber":2132}
	
        json_error_t error;
        json_t* response = JSON_LOADS(data, &error);
        if (!response) {
          applog(LOG_ERR, "json parse failed at line %d: %s\n%s",
                 error.line, error.text, data);
        }

	//[15:03:44 INF] New block mined 0000000000000004ac313527db1aa27bd22fe8190789a041818af0eb27c65418b30960f800000770ba2c026f810f818041eb355394a6a48751283111cb0b19ef569fca2e6690d59200000164434611401d1bc5941f835a504eb917120000000000a3c392
//[15:03:44 INF] HEADER: 0000000000000004ac313527db1aa27bd22fe8190789a041818af0eb27c65418b30960f800000770ba2c026f810f818041eb355394a6a48751283111cb0b19ef569fca2e6690d59200000164434611401d1bc5941f835a504eb917120000000000a3c392
//[15:03:44 INF] HASH: 000000037f996e75765f057dba76f406d45233327e3cdbc6e16d330e9fcfbda6
//[15:03:44 INF] NONCE: 2.2707579380895E+18, 10732434

//0000000000000001e2f46235e26b77077ae9d8f81d99140d5ebf2ae9efbe4473e183ef720000086c35ff65ea97926b95d928e552033fdd70ba3fb8f7a8dd59217b5e7af570911743000001644780c9421d2686787cf07c8ba02e34a90000000000514fea

	uint32_t test_data[25] =
	  {
	   // version
	   0x00000000,
	   // parent hash
	   0x00000001,
	   0xe2f46235,
	   0xe26b7707,
	   0x7ae9d8f8,
	   0x1d99140d,
	   0x5ebf2ae9,
	   0xefbe4473,
	   0xe183ef72,
	   // block number
	   0x0000086c,
	   // commitments
	   0x35ff65ea,
	   0x97926b95,
	   0xd928e552,
	   0x033fdd70,
	   0xba3fb8f7,
	   0xa8dd5921,
	   0x7b5e7af5,
	   0x70911743,
	   // timestamp
	   0x00000164,
	   0x4780c942,
	   // difficulty
	   0x1d268678,
	   // nonce
	   0x7cf07c8b,
	   0xa02e34a9,
	   0x00000000,
	   0x00000000,
	   //	   0x00514fea,
	  };

	json_t* header_json = json_object_get(response, "header");
        if (!header_json) {
          applog(LOG_ERR, "response does not contain header");
        }

        json_t* target_json = json_object_get(response, "target");
        if (!target_json) {
          applog(LOG_ERR, "response does not contain target");
        }

	const char* target_value = json_string_value(target_json);
	uint32_t target[8];
	for (int i = 0; i < 8; ++i) {
	  hex2bin(&target[i], target_value + i * 8, 8);
	  work->target[i] = swab32(target[i]);
	}
	work->targetdiff = target_to_diff(work->target);

	const char* header = json_string_value(header_json);

	uint32_t work_data[25];
	hex2bin((uint8_t*)work_data, header, 100);
	for (int i = 0; i < 25; ++i) {
	  work->data[i] = work_data[i];
	}

	// use work ntime as job id
	cbin2hex(work->job_id, (const char*)&work->data[18], 8);
	calc_network_diff(work);

	return true;
}

bool zenprotocol_submit(CURL *curl, struct pool_infos *pool, struct work *work)
{
	char curl_err_str[CURL_ERROR_SIZE] = { 0 };
	struct data_buffer all_data = { 0 };
	struct curl_slist *headers = NULL;
	char buf[256] = { 0 };
	char url[512];

        if (opt_protocol)
          applog_hex(work->data, 100);

        snprintf(url, 512, "%s/blockchain/submitheader", pool->url);

	uint32_t work_data[25];
	for (int i = 0; i < 25; ++i) {
	  work_data[i] = work->data[i];
	}

	cbin2hex(buf, (const char*)&work_data, 100);
	std::string body = "{\"header\": \"" +  std::string(buf) + "\"}";

	if (opt_protocol)
		curl_easy_setopt(curl, CURLOPT_VERBOSE, 1);
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_ENCODING, "");
	curl_easy_setopt(curl, CURLOPT_FAILONERROR, 0);
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt(curl, CURLOPT_TCP_NODELAY, 1);
	curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_err_str);
	curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10);

	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &all_data);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, zenprotocol_data_cb);

	curl_easy_setopt(curl, CURLOPT_POST, 1);
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());

	headers = curl_slist_append(headers, "Host: 0.0.0.0:31567");
	headers = curl_slist_append(headers, "Content-Type: application/json");
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

	int res = curl_easy_perform(curl) == 0;
	long errcode;
	CURLcode c = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &errcode);

        if (opt_debug)
                applog(LOG_DEBUG, "result: %d; errcode: %d", res, errcode);
	if (errcode != 200) {
		if (strlen(curl_err_str))
			applog(LOG_ERR, "submit err %ld %s", errcode, curl_err_str);
		res = 0;
	}
        if (opt_protocol)
          applog(LOG_DEBUG, "received %d bytes: %s", (int) all_data.len, all_data.buf);

	share_result(res, work->pooln, work->sharediff[0], res ? NULL : (char*) all_data.buf);

	curl_slist_free_all(headers);
	return true;
}

// ---- END ZENPROTOCOL LONGPOLL ----------------------------------------------------------------------------
