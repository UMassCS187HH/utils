#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'

OUTPUT_PATH = 'student_projects'

class Project
    DEFAULT_EXCLUSIONS = ['bin','libs', 'extras.json', 'tests.py', 'out', '*.iml', '.idea']

    def initialize(name, project)
        @name = name
        @project = project
    end

    def build_project
        cleanup_previous

        build_doc

        build_graded

        build_student
    end

    private

    def project_path
        return @project['directory']
    end

    def exclusions
        files = DEFAULT_EXCLUSIONS
        files += @project['private_files'] if @project['private_files']

        files.collect{|f| Dir.glob(f)}
    end

    def doc_dir
        File.join(project_path, "document")
    end

    def eclipse_projects_dir
        File.join(project_path, 'eclipse-projects')
    end

    def graded_zip
        "#{@name}-graded.zip"
    end

    def student_zip
        "#{@name}-student.zip"
    end

    def graded_dir
        "#{@name}-graded"
    end

    def student_dir
        "#{@name}-student"
    end

    def cleanup_previous
        Dir.chdir(OUTPUT_PATH) do
            FileUtils.rm_rf(student_dir)
            FileUtils.rm_rf(graded_dir)
            FileUtils.rm_f(student_zip)
        end

        Dir.chdir(eclipse_projects_dir) do
            FileUtils.rm_f(graded_zip)
        end
    end


    def build_doc
        Dir.chdir(doc_dir) do
            cmd = 'pdflatex project.tex'
            system(cmd)
            system(cmd)
        end

        pdf_path =  File.join(OUTPUT_PATH, "#{@name}-instructions.pdf")
        FileUtils.cp(File.join(doc_dir, 'project.pdf'), pdf_path)
    end

    def build_student
        raise "Must build graded first" if !File.exist?(File.join(OUTPUT_PATH,"#{graded_zip}"))

        Dir.chdir(OUTPUT_PATH) do
            cmd = "unzip #{graded_zip}"
            puts cmd
            system(cmd)

            FileUtils.mv("#{@name}-graded", student_dir)

            sanitize_project(student_dir)

            cmd = "zip -r #{student_zip} #{student_dir}"
            puts cmd
            system(cmd)

            FileUtils.rm_rf(student_dir)
        end
    end

    def build_graded
        # An effect of using zip is that sumbolic links get turned into files, so linked libs/jars become properly duplicated into this zip
        Dir.chdir(eclipse_projects_dir) do
            #poor man's clean, should add an ant clean to all projects instead
            FileUtils.rm_rf(File.join(graded_dir,'bin'))

            cmd = "zip -r #{graded_zip} #{graded_dir}"
            puts cmd
            system(cmd)
        end

        FileUtils.mv(File.join("#{eclipse_projects_dir}","#{graded_zip}"), OUTPUT_PATH)
    end

    def sanitize_code(file)
        tmp_file = "#{file}.tmp"

        out = File.open(tmp_file, 'w')

        in_private_code = false

        File.open(file).each_line{|l|
            if l =~ /BEGIN PRIVATE CODE/
                in_private_code = true
            end

            if l =~ /END PRIVATE CODE/
                in_private_code = false
                next
            end

            next if l =~ /STUDENT CODE/ || in_private_code

            out.write(l)
       }
       out.close

       FileUtils.mv(tmp_file,file)
    end

    def sanitize_test(file)
        # remove scored lines from tests: @Scored(points=2), and all private tests
        if file =~ /Private/i
            FileUtils.rm_f(file)
            return
        end

        tmp_file = "#{file}.tmp"

        out = File.open(tmp_file, 'w')

        File.open(file, 'r').each_line{|l|
            l.gsub!(/@GradedTest.*\(.*\)/,'')
            next if l =~ /import com\.gradescope/
            next if l =~ /PrivateTestHelpers/ # Found in the bst-scapegoat project
            out.write(l)
        }
        out.close

        FileUtils.mv(tmp_file,file)
    end

    def rename_project
        file = '.project'

        tmp_file = "#{file}.tmp"
        out = File.open(tmp_file, 'w')

        File.open(file, 'r').each_line{|l|
            l.gsub!('graded','student')
            out.write(l)
        }
        out.close

        FileUtils.mv(tmp_file,file)
    end

    def sanitize_project(dir)
        Dir.chdir(dir) do
            # Remove ant build files
            FileUtils.rm_f(Dir.glob('build.*'))

            # remove gradescope
            FileUtils.rm_rf('./support/com/gradescope')

            Dir.glob('test/**/*.java') {|f| sanitize_test(f)}

            # remove solution code
            Dir.glob('src/**/*.java') { |f| sanitize_code(f) }

            # remove excluded files
            exclusions.each { |f| FileUtils.rm_r(f)}

            # rename project
            rename_project
        end
    end
end


FileUtils.mkdir_p(OUTPUT_PATH)

projects = YAML.load_file('projects.yml')

projects.each{|project,definition|
    p = Project.new(project, definition)
    p.build_project
}
