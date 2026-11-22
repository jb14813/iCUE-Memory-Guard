"""Derive one exact 5.54.46 service image privately; never modify the input."""
import hashlib
import struct
from pathlib import Path

import pefile

SOURCE_SHA256 = '8e57fd673fb93f3944c840dec3604fdc225e981175059d7c7c038d558a30566c'
CALLS = (0xF098, 0xF1C8, 0xF3FB, 0xF51B, 0xFD2B, 0x1033B, 0x1064B, 0x1077B, 0x108AB, 0x10D5D, 0x1100B)
COPY, FAILURE = 0xE090, 0x10A5C


def align(n, boundary):
    return (n + boundary - 1) & ~(boundary - 1)


def patch_bytes(source):
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError('Only the verified unmodified 5.54.46 service is supported')
    pe = pefile.PE(data=source)
    for call in CALLS:
        if pe.get_data(call, 5) != b'\xe8' + struct.pack('<i', COPY - call - 5):
            raise ValueError('Owned BSTR copy site changed')
    if pe.get_data(FAILURE, 7) != bytes.fromhex('488b4f2841ffd2'):
        raise ValueError('Sensor query call ABI changed')
    old_exception = pe.OPTIONAL_HEADER.DATA_DIRECTORY[3]
    old_entries = pe.get_data(old_exception.VirtualAddress, old_exception.Size)
    if old_exception.Size % 12 or len(old_entries) != old_exception.Size:
        raise ValueError('Invalid original unwind directory')
    head = pe.sections[-1].get_file_offset() + 40
    if head + 80 > pe.OPTIONAL_HEADER.SizeOfHeaders or any(source[head:head+80]):
        raise ValueError('No empty section-header space')
    sa, fa = pe.OPTIONAL_HEADER.SectionAlignment, pe.OPTIONAL_HEADER.FileAlignment
    code_va = align(max(s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData) for s in pe.sections), sa)
    code_size = 0x200 + len(old_entries) + 24
    data_va = align(code_va + code_size, sa)
    copy_va, fail_va = code_va, code_va + 0x80

    count = len(pe.DIRECTORY_ENTRY_IMPORT)
    descriptor_size = (count + 2)*20
    imports = bytearray(descriptor_size)
    original_imports = pe.OPTIONAL_HEADER.DATA_DIRECTORY[1]
    imports[:count*20] = pe.get_data(original_imports.VirtualAddress, count*20)

    def append_data(blob, boundary=1):
        imports.extend(bytes(align(len(imports), boundary)-len(imports)))
        rva = data_va + len(imports)
        imports.extend(blob)
        return rva

    dll_va = append_data(b'OLEAUT32.dll\0')
    name_va = append_data(b'\0\0SysFreeString\0', 2)
    int_va = append_data(struct.pack('<QQ', name_va, 0), 8)
    iat_va = append_data(struct.pack('<QQ', name_va, 0), 8)
    struct.pack_into('<IIIII', imports, count*20, int_va, 0, 0, dll_va, iat_va)

    def call(code, rva, destination):
        code.extend(b'\xe8' + struct.pack('<i', destination-(rva+len(code)+5)))

    def free(code, rva):
        code.extend(b'\xff\x15' + struct.pack('<i', iat_va-(rva+len(code)+6)))

    copy = bytearray.fromhex('4883ec384889542420')
    call(copy, copy_va, COPY)
    copy += bytes.fromhex('4889442428488b4c2420')
    free(copy, copy_va)
    copy += bytes.fromhex('488b4424284883c438c3')
    copy_unwind = align(copy_va + len(copy), 4)

    fail = bytearray.fromhex('4883ec68488b4f28')
    for n in range(6):
        fail += bytes.fromhex('488b8424')+struct.pack('<I',0x90+n*8)
        fail += bytes.fromhex('48894424')+bytes([0x20+n*8])
    fail += bytes.fromhex('4c8b5c24284c895c24504d85db')
    patches = []

    def branch(opcode, label):
        fail.extend([opcode,0]); patches.append((len(fail)-1,label))

    branch(0x74,'invoke')
    fail += bytes.fromhex('49c70300000000')
    labels = {'invoke':len(fail)}
    fail += bytes.fromhex('41ffd28944245885c0')
    branch(0x75,'done')
    fail += bytes.fromhex('4c8b5c24504d85db')
    branch(0x74,'done')
    fail += bytes.fromhex('498b0b49c70300000000')
    free(fail,fail_va)
    labels['done'] = len(fail)
    fail += bytes.fromhex('8b4424584883c468c3')
    for at,label in patches:
        displacement = labels[label]-at-1
        if not -128 <= displacement <= 127:
            raise ValueError('Cleanup branch exceeds short encoding')
        fail[at] = displacement & 255
    fail_unwind = align(fail_va + len(fail),4)
    if copy_unwind+8 > fail_va or fail_unwind+8 > code_va+0x200:
        raise ValueError('Cleanup functions overlap metadata')
    code = bytearray(code_size)
    code[:len(copy)] = copy
    code[copy_unwind-code_va:copy_unwind-code_va+8] = bytes([1,4,1,0,4,0x62,0,0])
    code[fail_va-code_va:fail_va-code_va+len(fail)] = fail
    code[fail_unwind-code_va:fail_unwind-code_va+8] = bytes([1,4,1,0,4,0xC2,0,0])
    code[0x200:0x200+len(old_entries)] = old_entries
    struct.pack_into('<IIIIII',code,0x200+len(old_entries),copy_va,copy_va+len(copy),copy_unwind,fail_va,fail_va+len(fail),fail_unwind)
    raw_code = align(len(source),fa)
    raw_data = raw_code+align(len(code),fa)
    result = bytearray(source)
    result.extend(bytes(raw_data+align(len(imports),fa)-len(result)))
    result[raw_code:raw_code+len(code)] = code
    result[raw_data:raw_data+len(imports)] = imports
    for offset,name,virtual,va,raw_size,raw,flags in [
        (head,b'.jzbc',len(code),code_va,align(len(code),fa),raw_code,0x60000020),
        (head+40,b'.jzbi',len(imports),data_va,align(len(imports),fa),raw_data,0xC0000040),
    ]:
        struct.pack_into('<8sIIIIIIHHI',result,offset,name,virtual,va,raw_size,raw,0,0,0,0,flags)

    def set_field(obj, field, value):
        struct.pack_into('<I',result,obj.get_field_absolute_offset(field),value)

    struct.pack_into('<H',result,pe.FILE_HEADER.get_field_absolute_offset('NumberOfSections'),pe.FILE_HEADER.NumberOfSections+2)
    set_field(pe.OPTIONAL_HEADER,'SizeOfImage',align(data_va+len(imports),sa))
    set_field(pe.OPTIONAL_HEADER,'SizeOfCode',pe.OPTIONAL_HEADER.SizeOfCode+align(len(code),fa))
    set_field(pe.OPTIONAL_HEADER,'SizeOfInitializedData',pe.OPTIONAL_HEADER.SizeOfInitializedData+align(len(imports),fa))
    for index,rva,size in [(1,data_va,descriptor_size),(3,code_va+0x200,len(old_entries)+24),(4,0,0),(11,0,0)]:
        entry=pe.OPTIONAL_HEADER.DATA_DIRECTORY[index]
        set_field(entry,'VirtualAddress',rva);set_field(entry,'Size',size)
    for site in CALLS:
        at=pe.get_offset_from_rva(site)
        result[at:at+5]=b'\xe8'+struct.pack('<i',copy_va-site-5)
    at=pe.get_offset_from_rva(FAILURE)
    result[at:at+7]=b'\xe8'+struct.pack('<i',fail_va-FAILURE-5)+b'\x90\x90'
    set_field(pe.OPTIONAL_HEADER,'CheckSum',0)
    final=pefile.PE(data=bytes(result))
    set_field(pe.OPTIONAL_HEADER,'CheckSum',final.generate_checksum())
    return bytes(result)


if __name__ == '__main__':
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.source.resolve()==args.output.resolve():
        raise ValueError('Source must remain untouched')
    data=patch_bytes(args.source.read_bytes())
    with args.output.open('xb') as stream:
        stream.write(data)
    print(hashlib.sha256(data).hexdigest())
