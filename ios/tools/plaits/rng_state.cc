// Состояние генератора случайных чисел stmlib после init() голосов (jambo_voices.cc) — для самотеста Swift:
// эталоны считаются на свежем экземпляре, поэтому Swift перед каждым случаем ставит это состояние.
#include <cstdio>
#include "stmlib/utils/random.h"
extern "C" void init();
int main() {
  init();
  printf("0x%08X\n", stmlib::Random::state());
  return 0;
}
