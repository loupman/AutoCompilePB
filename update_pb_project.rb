require 'xcodeproj'

##
# **请设置PB文件（pb_path）的路径
# **请保持以下的目录结构
#
#  --LLProtocBuffer
#  ----ProtocolBuffers  GOOGLE PB SDK文件
#  ----sourcecode  PB文件所有的目录文件
#  ----update_pb_project.rb  本文件
#  --LLProtocBuffer.xcodeproj
#
#
pb_path = '/Users/lihua/Desktop/Workspace/proto'
tmp_pb_dir_name = 'protoc_lh_mer_dir'   # 本地编译临时文件
current_path = Dir::getwd
$source_path = current_path + '/sourcecode'   #全局变量
project_path = current_path + '/../LLProtocBuffer.xcodeproj'

puts('-----------------PB文件目录-------')
puts(pb_path)
puts('-----------------项目目录（包含到xcodeproj）-------')
puts(project_path)

print('请确认PB文件和项目目录是否正确，如不正确请先修改。是否继续[y|n]: ')
confirm = gets.chomp()
if confirm.downcase!='y' && confirm.downcase!='yes'
    abort("您没有选择继续，终止程序！")
end

# 检查环境
xcproj = `xcodeproj --version`
if xcproj.include?('command not found')
    puts('-----------------Installing xcodeproj（need ruby environment）-------')
    `sudo gem install xcodeproj`
end
protoc = `protoc --version`
if protoc.include?('command not found')
    puts('-----------------Please install protoc first-------')
    abort("您没有安装protoc，请先安装。地址为- https://github.com/google/protobuf.git")
end

#----------------- start of some pre-defined methods ------------------
def getFileName(filePath, includeExtension = true)
    file_name = filePath
    if file_name.include?('/')
         index = file_name.rindex('/')
         file_name = file_name[index+1, file_name.length]
    end
    if file_name.include?('.') && !includeExtension
        index = file_name.rindex('.')
        file_name = file_name[0, index]
    end
    return file_name
end

def getLastFolder(filePath, level=1)
    if level <0
        return filePath
    end
    
    file_name = filePath
    file_name.sub('//', '/')
    components = file_name.split('/')
    
    if components.length > level
        return components[ components.length - level - 1 ]
    end
    
    return file_name
end

def isEmptyFolder(filePath)
    if File.directory?(filePath)
        Dir.foreach(filePath) do |filename|
            if filename != "." and filename != ".."
                isEmptyFolder(filePath + "/" + filename)
            end
        end
        Dir.delete(filePath)
    end
end

class SVNUpdateFile
    attr_accessor :svn_status, :file_path, :file_name
    
    def initialize(svnStatus,filePath)
        self.svn_status = svnStatus
        self.file_path = filePath
        self.file_name = getFileName(filePath, true)
    end
    
    def to_s
        "{file_name:#{file_name}, svn_status:#{svn_status}, file_path:#{file_path}}"
    end
end

#----------------- end of some pre-defined methods ------------------

#----------------- Updating PB files ------------------

#重设PB更新的临时目录   如果有文件则说明上次添加文件失败了，重新添加到项目
$tmp_pb_dir = "#{pb_path}/#{tmp_pb_dir_name}"
if File.exist?($tmp_pb_dir) and File.directory?($tmp_pb_dir)
    puts('----------------- 查找上一次PB编译文件夹中没有更新到项目中的文件!-------')
    Dir.foreach($tmp_pb_dir) do |filename|
        if filename != "." and filename != ".."
            traverseAndUpdateProj($tmp_pb_dir + "/" + filename)
        end
    end
end

if File.exist?($tmp_pb_dir) && File::directory?($tmp_pb_dir)
    system "rm -rf #{$tmp_pb_dir}"
end

#----------------- Updating SVN ------------------
Dir::chdir(pb_path)

puts('-----------------Updating SVN...')
svn_res = `svn update`
puts('-----------------Updated SVN Result...')
puts(svn_res)
#A  Added         D  Deleted     U  Updated
#C  Conflict      G  Merged      E  Existed     R  Replaced
#只处理这几种更新
svn_status_arr = ['A', 'U', 'R']

arr = svn_res.split("\n")
updatefiles = []
    # for mockup data
    # SVNUpdateFile.new('A', 'common/Version.proto'),
    # SVNUpdateFile.new('A', 'core/FetchRouteRequest.proto')
$hasAddFile = true
arr.each { |item| 
    strs = item.lstrip.split
    #仅仅添加 proto结尾的文件
    if strs.length>1 and svn_status_arr.include?(strs.at(0)) and strs.at(1)=~/.\.proto$/
        obj = SVNUpdateFile.new(strs.at(0), strs.at(1))
        updatefiles.push obj
        if obj.svn_status == 'A'
            hasAddFile = true
        end
    end
}

puts('-----------------需要编译的文件列表如下：-------')
puts(updatefiles)

if updatefiles.length == 0
    abort('-----------------SVN没有任何更新!-------')
end

#切换到PB文件的目录
Dir::chdir(pb_path)
Dir::mkdir(tmp_pb_dir_name, mode=0740)

#编译pb文件
puts('----------------- 编译从SVN中更新的PB文件!-------')
updatefiles.each { |item|
    # item isKindOf SVNUpdateFile
    `protoc --objc_out=./#{tmp_pb_dir_name} ./#{item.file_path}`  # no output message
}

# #增量添加文件到项目中去
require 'xcodeproj'
$targets
$project
if $hasAddFile
    $project = Xcodeproj::Project.open(project_path)
    $targets = $project.targets
end

# 遍历文件夹中的所有.h和.m 文件，把他们添加到项目中去
def traverseAndUpdateProj(filePath)
    # 文件夹，遍历它的子文件夹
    if File.directory?(filePath)
        Dir.foreach(filePath) do |filename|
            if filename != "." and filename != ".."
                traverseAndUpdateProj(filePath + "/" + filename)
            end
        end
        Dir::delete(filePath) # 删除空文件夹，否则无法删除
    else
       index = filePath.rindex($tmp_pb_dir)
       relateddir = filePath[index+$tmp_pb_dir.length, filePath.length]
       targetdir = $source_path + relateddir

       if File.exist?(targetdir)
            puts("--- copying file #{targetdir} ")
            res = `cp -f #{filePath}  #{targetdir}`
            if res.length == 0
                `rm -rf #{filePath}`
            end
       elsif $hasAddFile
            $targets.each { |target|
                puts("--- adding file #{targetdir}")

                # copying to project reference
                if !target.name.include?("Test")
                    
                    folderInProj = getLastFolder(targetdir, 1)
                    joined = File.join(getLastFolder(targetdir, 3), getLastFolder(targetdir, 2), folderInProj);
                    group = $project.main_group.find_subpath(joined, true)
                    group.set_source_tree('<group>')
                    group.set_path(folderInProj)
                    file_ref = group.new_reference(targetdir)

                    target.add_file_references([file_ref])
                    $project.save
                    
                    # copying file to project folder
                    res = `cp -f #{filePath}  #{targetdir}`
                    if res.length == 0
                        `rm -rf #{filePath}`
                    end
                end
            }
       end
    end
end

Dir::chdir(current_path)

puts('----------------- 更新编译之后的文件到项目中!-------')
traverseAndUpdateProj($tmp_pb_dir)






