#ifndef VIZOR_TEST_SHLOBJ_H_
#define VIZOR_TEST_SHLOBJ_H_

constexpr long SHCNE_ASSOCCHANGED = 0x08000000;
constexpr unsigned int SHCNF_IDLIST = 0;
void SHChangeNotify(long, unsigned int, const void*, const void*);

#endif
