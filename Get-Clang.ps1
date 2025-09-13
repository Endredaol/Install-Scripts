$llvmGpgKeyUrl = "https://apt.llvm.org/llvm-snapshot.gpg.key"
$llvmAptRepoFile = "/etc/apt/sources.list.d/llvm.list"

Invoke-WebRequest -Uri $llvmGpgKeyUrl -OutFile "/tmp/llvm-snapshot.gpg.key"

"cat /tmp/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc" | Invoke-Expression

@"
deb http://apt.llvm.org/unstable/ llvm-toolchain-21 main
deb-src http://apt.llvm.org/unstable/ llvm-toolchain-21 main
"@ | Set-Content -Path $llvmAptRepoFile

"sudo apt-get update" | Invoke-Expression
"sudo apt-get install -y clang-21" | Invoke-Expression

sudo ln -sf /usr/bin/clang-21 /usr/bin/clang
sudo ln -sf /usr/bin/clang++-21 /usr/bin/clang++

"clang  --version" | Invoke-Expression