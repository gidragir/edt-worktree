function Invoke-EdtWtGit {
    <#
      Выполняет git с принудительной установкой кодировки вывода UTF-8 и флагом core.quotepath=false.
      Предотвращает искажение путей и веток с кириллицей (cp866/кракозябры ╨Ш╨╜╤В...).
    #>
    $prevEnc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        & git -c core.quotepath=false @args
    } finally {
        [Console]::OutputEncoding = $prevEnc
    }
}
