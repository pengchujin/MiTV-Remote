#ifndef CECPrivateBridge_h
#define CECPrivateBridge_h

#include <stdbool.h>
#include <stdint.h>

bool TVCECPrivateCheck(char **errorMessage);
bool TVCECPrivateBecomeActiveSource(char **errorMessage);
bool TVCECPrivateSendUserControl(uint8_t command, char **errorMessage);
void TVCECPrivateFreeMessage(char *message);

#endif
